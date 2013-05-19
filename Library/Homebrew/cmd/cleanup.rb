require 'formula'
require 'keg'
require 'bottles'

module Homebrew extend self

  def cleanup
    return unless HOMEBREW_CELLAR.directory?

    if ARGV.named.empty?
      cleanup_cellar
      cleanup_cache
      rm_DS_Store unless ARGV.dry_run?
    else
      ARGV.formulae.each { |f| cleanup_formula(f) }
    end
  end

  def cleanup_cellar
    HOMEBREW_CELLAR.subdirs.each do |rack|
      begin
        cleanup_formula Formula.factory(rack.basename.to_s)
      rescue FormulaUnavailableError
        # Don't complain about directories from DIY installs
      end
    end
  end

  def cleanup_formula f
    if f.installed?
      eligible_kegs = f.rack.subdirs.map { |d| Keg.new(d) }.select { |k| f.version > k.version }
      eligible_kegs.each do |keg|
        if f.can_cleanup?
          cleanup_keg(keg)
        else
          opoo "Skipping (old) keg-only: #{keg}"
        end
      end
    elsif f.rack.subdirs.length > 1
      # If the cellar only has one version installed, don't complain
      # that we can't tell which one to keep.
      opoo "Skipping #{f.name}: most recent version #{f.version} not installed"
    end
  end

  def cleanup_keg keg
    if keg.linked?
      opoo "Skipping (old) #{keg} due to it being linked"
    elsif ARGV.dry_run?
      puts "Would remove: #{keg}"
    else
      puts "Removing: #{keg}..."
      keg.rmtree
    end
  end

  def cleanup_cache
    HOMEBREW_CACHE.children.select(&:file?).each do |file|
      version = file.version
      name = file.basename.to_s.match(/(.*)-(?:#{Regexp.escape(version)})/).captures.first rescue nil
      next unless name && version

      begin
        f = Formula.factory(name)
      rescue FormulaUnavailableError
        next
      end

      if f.version > version || ARGV.switch?('s') && !f.installed? || bottle_file_outdated?(f, file)
        cleanup_cached_file(file)
      end
    end
  end

  def cleanup_cached_file file
    if ARGV.dry_run?
      puts "Would remove: #{file}"
    else
      puts "Removing: #{file}..."
      file.unlink
    end
  end

  def rm_DS_Store
    system "find #{HOMEBREW_PREFIX} -name .DS_Store -delete 2>/dev/null"
  end

end

class Formula
  def can_cleanup?
    # It used to be the case that keg-only kegs could not be cleaned up, because
    # older brews were built against the full path to the keg-only keg. Then we
    # introduced the opt symlink, and built against that instead. So provided
    # no brew exists that was built against an old-style keg-only keg, we can
    # remove it.
    if not keg_only? or ARGV.force?
      true
    elsif opt_prefix.directory?
      # SHA records were added to INSTALL_RECEIPTS the same day as opt symlinks
      !Formula.installed.
        select{ |ff| ff.deps.map{ |d| d.to_s }.include? name }.
        map{ |ff| ff.rack.subdirs rescue [] }.
        flatten.
        map{ |keg_path| Tab.for_keg(keg_path).send("HEAD") }.
        include? nil
    end
  end
end
