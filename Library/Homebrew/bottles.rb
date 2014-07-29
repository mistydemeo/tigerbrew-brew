require 'tab'
require 'os/mac'
require 'extend/ARGV'
require 'bottle_version'

def built_as_bottle? f
  return false unless f.installed?
  tab = Tab.for_keg(f.installed_prefix)
  tab.built_as_bottle
end

def bottle_file_outdated? f, file
  filename = file.basename.to_s
  return unless f.bottle && filename.match(Pathname::BOTTLE_EXTNAME_RX)

  bottle_ext = filename[bottle_native_regex, 1]
  bottle_url_ext = f.bottle.url[bottle_native_regex, 1]

  bottle_ext && bottle_url_ext && bottle_ext != bottle_url_ext
end

def bottle_native_regex
  /(\.#{bottle_tag}\.bottle\.(\d+\.)?tar\.gz)$/o
end

def bottle_tag
  if MacOS.version >= :lion
    MacOS.cat
  elsif MacOS.version == :snow_leopard
    Hardware::CPU.is_64_bit? ? :snow_leopard : :snow_leopard_32
  else
    # Return, e.g., :tiger_g3, :leopard_g5_64, :leopard_64 (which is Intel)
    if Hardware::CPU.type == :ppc
      tag = "#{MacOS.cat}_#{Hardware::CPU.family}".to_sym
    else
      tag = MacOS.cat
    end
    MacOS.prefer_64_bit? ? "#{tag}_64".to_sym : tag
  end
end

def bottle_filename_formula_name filename
  path = Pathname.new filename
  version = BottleVersion.parse(path).to_s
  basename = path.basename.to_s
  basename.rpartition("-#{version}").first
end

class BottleCollector
  def initialize
    @checksums = {}
  end

  def fetch_checksum_for(tag)
    tag = find_matching_tag(tag)
    return self[tag], tag if tag
  end

  def keys
    @checksums.keys
  end

  def [](key)
    @checksums[key]
  end

  def []=(key, value)
    @checksums[key] = value
  end

  def key?(key)
    @checksums.key?(key)
  end

  private

  def find_matching_tag(tag)
    if key?(tag)
      tag
    else
      find_altivec_tag(tag) || find_or_later_tag(tag)
    end
  end

  # This allows generic Altivec PPC bottles to be supported in some
  # formulae, while also allowing specific bottles in others; e.g.,
  # sometimes a formula has just :tiger_altivec, other times it has
  # :tiger_g4, :tiger_g5, etc.
  def find_altivec_tag(tag)
    if tag.to_s =~ /(\w+)_(g4|g4e|g5)$/
      altivec_tag = "#{$1}_altivec".to_sym
      altivec_tag if key?(altivec_tag)
    end
  end

  # Allows a bottle tag to specify a specific OS or later,
  # so the same bottle can target multiple OSs.
  # Not used in core, used in taps.
  def find_or_later_tag(tag)
    begin
      tag_version = MacOS::Version.from_symbol(tag)
    rescue ArgumentError
      return
    end

    keys.find do |key|
      if key.to_s.end_with?("_or_later")
        later_tag = key.to_s[/(\w+)_or_later$/, 1].to_sym
        MacOS::Version.from_symbol(later_tag) <= tag_version
      end
    end
  end
end
