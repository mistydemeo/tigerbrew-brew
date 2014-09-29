require 'formula'
require 'keg'

module Homebrew
  def switch
    if ARGV.named.length != 2
      onoe "Usage: brew switch <formula> <version>"
      exit 1
    end

    name = ARGV.shift
    version = ARGV.shift

    # Does this formula have any versions?
    f = Formula.factory(name.downcase)
    cellar = f.prefix.parent
    unless cellar.directory?
      onoe "#{name} not found in the Cellar."
      exit 2
    end

    # Does the target version exist?
    unless (cellar+version).directory?
      onoe "#{name} does not have a version \"#{version}\" in the Cellar."

      versions = cellar.subdirs.map { |d| Keg.new(d).version }
      puts "Versions available: #{versions.join(', ')}"

      exit 3
    end

    # Unlink all existing versions
    cellar.subdirs.each do |v|
      keg = Keg.new(v)
      puts "Cleaning #{keg}"
      keg.unlink
    end

    # Link new version, if not keg-only
    if f.keg_only?
      keg = Keg.new(cellar+version)
      keg.optlink
      puts "Opt link created for #{keg}"
    else
      keg = Keg.new(cellar+version)
      puts "#{keg.link} links created for #{keg}"
    end
  end
end
