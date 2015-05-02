require 'formula'
require 'bottles'
require 'tab'
require 'keg'
require 'formula_versions'
require 'utils/inreplace'
require 'erb'
require 'extend/pathname'

BOTTLE_ERB = <<-EOS
  bottle do
    <% if root_url != BottleSpecification::DEFAULT_ROOT_URL %>
    root_url "<%= root_url %>"
    <% end %>
    <% if prefix != BottleSpecification::DEFAULT_PREFIX %>
    prefix "<%= prefix %>"
    <% end %>
    <% if cellar.is_a? Symbol %>
    cellar :<%= cellar %>
    <% elsif cellar != BottleSpecification::DEFAULT_CELLAR %>
    cellar "<%= cellar %>"
    <% end %>
    <% if revision > 0 %>
    revision <%= revision %>
    <% end %>
    <% checksums.each do |checksum_type, checksum_values| %>
    <% checksum_values.each do |checksum_value| %>
    <% checksum, osx = checksum_value.shift %>
    <%= checksum_type %> "<%= checksum %>" => :<%= osx %>
    <% end %>
    <% end %>
  end
EOS

module Homebrew
  def keg_contains string, keg, ignores
    @put_string_exists_header, @put_filenames = nil

    def print_filename string, filename
      unless @put_string_exists_header
        opoo "String '#{string}' still exists in these files:"
        @put_string_exists_header = true
      end

      @put_filenames ||= []
      unless @put_filenames.include? filename
        puts "#{Tty.red}#{filename}#{Tty.reset}"
        @put_filenames << filename
      end
    end

    result = false

    keg.each_unique_file_matching(string) do |file|
      # Check dynamic library linkage. Importantly, do not run otool on static
      # libraries, which will falsely report "linkage" to themselves.
      if file.mach_o_executable? or file.dylib? or file.mach_o_bundle?
        linked_libraries = file.dynamically_linked_libraries
        linked_libraries = linked_libraries.select { |lib| lib.include? string }
        result ||= linked_libraries.any?
      else
        linked_libraries = []
      end

      if ARGV.verbose?
        print_filename(string, file) if linked_libraries.any?
        linked_libraries.each do |lib|
          puts " #{Tty.gray}-->#{Tty.reset} links to #{lib}"
        end
      end

      # Use strings to search through the file for each string
      Utils.popen_read("strings", "-t", "x", "-", file.to_s) do |io|
        until io.eof?
          str = io.readline.chomp

          next if ignores.any? {|i| i =~ str }

          next unless str.include? string

          offset, match = str.split(" ", 2)

          next if linked_libraries.include? match # Don't bother reporting a string if it was found by otool
          result ||= true

          if ARGV.verbose?
            print_filename string, file
            puts " #{Tty.gray}-->#{Tty.reset} match '#{match}' at offset #{Tty.em}0x#{offset}#{Tty.reset}"
          end
        end
      end
    end

    put_symlink_header = false
    keg.find do |pn|
      if pn.symlink? && (link = pn.readlink).absolute?
        if !put_symlink_header && link.to_s.start_with?(string)
          opoo "Absolute symlink starting with #{string}:"
          puts "  #{pn} -> #{pn.resolved_path}"
          put_symlink_header = true
        end

        result = true
      end
    end

    result
  end

  def bottle_output bottle
    erb = ERB.new BOTTLE_ERB
    erb.result(bottle.instance_eval { binding }).gsub(/^\s*$\n/, '')
  end

  def bottle_formula f
    unless f.installed?
      return ofail "Formula not installed or up-to-date: #{f.name}"
    end

    unless built_as_bottle? f
      return ofail "Formula not installed with '--build-bottle': #{f.name}"
    end

    unless f.stable
      return ofail "Formula has no stable version: #{f.name}"
    end

    if ARGV.include? '--no-revision'
      bottle_revision = 0
    else
      ohai "Determining #{f.name} bottle revision..."
      versions = FormulaVersions.new(f)
      max = versions.bottle_version_map("origin/master")[f.pkg_version].max
      bottle_revision = max ? max + 1 : 0
    end

    filename = Bottle::Filename.create(f, bottle_tag, bottle_revision)

    if bottle_filename_formula_name(filename).empty?
      return ofail "Add a new regex to bottle_version.rb to parse #{f.version} from #{filename}"
    end

    bottle_path = Pathname.pwd/filename

    prefix = HOMEBREW_PREFIX.to_s
    cellar = HOMEBREW_CELLAR.to_s

    ohai "Bottling #{filename}..."

    keg = Keg.new(f.prefix)
    relocatable = false

    keg.lock do
      begin
        keg.relocate_install_names prefix, Keg::PREFIX_PLACEHOLDER,
          cellar, Keg::CELLAR_PLACEHOLDER, :keg_only => f.keg_only?
        keg.delete_pyc_files!

        cd cellar do
          # Use gzip, faster to compress than bzip2, faster to uncompress than bzip2
          # or an uncompressed tarball (and more bandwidth friendly).
          safe_system 'tar', 'czf', bottle_path, "#{f.name}/#{f.pkg_version}"
        end

        if bottle_path.size > 1*1024*1024
          ohai "Detecting if #{filename} is relocatable..."
        end

        if prefix == '/usr/local'
          prefix_check = File.join(prefix, "opt")
        else
          prefix_check = prefix
        end

        ignores = []
        if f.deps.any? { |dep| dep.name == "go" }
          ignores << %r{#{HOMEBREW_CELLAR}/go/[\d\.]+/libexec}
        end

        relocatable = !keg_contains(prefix_check, keg, ignores)
        relocatable = !keg_contains(cellar, keg, ignores) && relocatable
        puts if !relocatable && ARGV.verbose?
      rescue Interrupt
        ignore_interrupts { bottle_path.unlink if bottle_path.exist? }
        raise
      ensure
        ignore_interrupts do
          keg.relocate_install_names Keg::PREFIX_PLACEHOLDER, prefix,
            Keg::CELLAR_PLACEHOLDER, cellar, :keg_only => f.keg_only?
        end
      end
    end

    root_url = ARGV.value("root-url")
    # Use underscored version for legacy reasons. Remove at some point.
    root_url ||= ARGV.value("root_url")

    bottle = BottleSpecification.new
    bottle.root_url(root_url) if root_url
    bottle.prefix prefix
    bottle.cellar relocatable ? :any : cellar
    bottle.revision bottle_revision
    bottle.sha256 bottle_path.sha256 => bottle_tag

    output = bottle_output bottle

    puts "./#{filename}"
    puts output

    if ARGV.include? '--rb'
      File.open("#{filename.prefix}.bottle.rb", "w") { |file| file.write(output) }
    end
  end

  module BottleMerger
    def bottle(&block)
      instance_eval(&block)
    end
  end

  def merge
    merge_hash = {}
    ARGV.named.each do |argument|
      formula_name = bottle_filename_formula_name argument
      merge_hash[formula_name] ||= []
      bottle_block = IO.read argument
      merge_hash[formula_name] << bottle_block
    end

    merge_hash.each do |formula_name, bottle_blocks|
      ohai formula_name

      bottle = BottleSpecification.new.extend(BottleMerger)
      bottle_blocks.each { |block| bottle.instance_eval(block) }

      output = bottle_output bottle
      puts output

      if ARGV.include? '--write'
        tap = ARGV.value('tap')
        canonical_formula_name = if tap
          "#{tap}/#{formula_name}"
        else
          formula_name
        end
        f = Formulary.factory(canonical_formula_name)
        update_or_add = nil

        Utils::Inreplace.inreplace(f.path) do |s|
          if s.include? 'bottle do'
            update_or_add = 'update'
            string = s.sub!(/  bottle do.+?end\n/m, output)
            odie 'Bottle block update failed!' unless string
          else
            update_or_add = 'add'
            if s.include? 'stable do'
              indent = s.slice(/^ +stable do/).length - "stable do".length
              string = s.sub!(/^ {#{indent}}stable do(.|\n)+?^ {#{indent}}end\n/m, '\0' + output + "\n")
            else
              string = s.sub!(/(
                                 \ {2}(                                                # two spaces at the beginning
                                   url\ ['"][\S\ ]+['"]                                # url with a string
                                   (
                                     ,[\S\ ]*$                                         # url may have options
                                     (\n^\ {3}[\S\ ]+$)*                               # options can be in multiple lines
                                   )?|
                                   (sha1|sha256|head|version|mirror)\ ['"][\S\ ]+['"]| # specs with a string
                                   revision\ \d+                                       # revision with a number
                                 )\n+                                                  # multiple empty lines
                               )+
                              /mx, '\0' + output + "\n")
            end
            odie 'Bottle block addition failed!' unless string
          end
        end

        HOMEBREW_REPOSITORY.cd do
          safe_system "git", "commit", "--no-edit", "--verbose",
            "--message=#{f.name}: #{update_or_add} #{f.pkg_version} bottle.",
            "--", f.path
        end
      end
    end
    exit 0
  end

  def bottle
    merge if ARGV.include? '--merge'

    ARGV.formulae.each do |f|
      bottle_formula f
    end
  end
end
