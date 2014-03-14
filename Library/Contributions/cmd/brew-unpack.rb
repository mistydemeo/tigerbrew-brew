require 'formula'

require 'stringio'
module ScriptDataReader
  # This module contains a method for extracting the contents of DATA from a
  # Ruby file other than the script containing the currently executing
  # function.  Many thanks to Glenn Jackman's Stackoverflow answer which
  # provided this code:
  #
  #   http://stackoverflow.com/questions/2156629/can-i-access-the-data-from-a-required-script-in-ruby/2157556#2157556
  def self.load(filename)
    data = StringIO.new
    File.open(filename) do |f|
      begin
        line = f.gets
      end until line.nil? or line.match(/^__END__$/)
      while line = f.gets
        data << line
      end
    end
    data.rewind
    data
  end
end

module UnpackPatch
  def patch
    return unless ARGV.flag? "--patch"

    begin
      old_verbose = $VERBOSE
      $VERBOSE = nil
      Formula.const_set "DATA", ScriptDataReader.load(path)
    ensure
      $VERBOSE = old_verbose
    end

    super
  end
end

module Homebrew extend self
  def unpack_usage; <<-EOS.undent
    Usage: brew unpack [-pg] [--destdir=path/to/extract/in] <formulae ...>

    Unpack formulae source code for inspection.

    Formulae archives will be extracted to subfolders inside the current working
    directory or a directory specified by `--destdir`. If the `-p` option is
    supplied, patches will also be downloaded and applied. If the `-g` option is
    specified a git repository is created and all files added so that you can diff
    changes.
    EOS
  end

  def unpack
    abort unpack_usage if ARGV.empty?

    formulae = ARGV.formulae
    raise FormulaUnspecifiedError if formulae.empty?

    if (dir = ARGV.value('destdir')).nil?
      unpack_dir = Pathname.pwd
    else
      unpack_dir = Pathname.new(dir)
      unpack_dir.mkpath unless unpack_dir.exist?
    end

    raise "Cannot write to #{unpack_dir}" unless unpack_dir.writable_real?

    formulae.each do |f|
      f.extend(UnpackPatch)

      # Create a nice name for the stage folder.
      stage_dir = unpack_dir + [f.name, f.version].join('-')

      if stage_dir.exist?
        raise "Destination #{stage_dir} already exists!" unless ARGV.force?
        rm_rf stage_dir
      end

      oh1 "Unpacking #{f.name} to: #{stage_dir}"
      ENV['VERBOSE'] = '1' # show messages about tar
      f.brew { cp_r getwd, stage_dir }
      ENV['VERBOSE'] = nil

      if ARGV.switch? 'g'
        ohai "Setting up git repository"
        cd stage_dir
        system "git", "init", "-q"
        system "git", "add", "-A"
        system "git", "commit", "-q", "-m", "brew-unpack"
      end
    end
  end
end

# Here is the actual code that gets run when `brew` loads this external
# command.
Homebrew.unpack
