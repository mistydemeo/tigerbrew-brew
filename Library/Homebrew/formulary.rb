# The Formulary is responsible for creating instances of Formula.
class Formulary

  def self.unload_formula formula_name
    Object.send(:remove_const, class_s(formula_name))
  end

  def self.formula_class_defined? formula_name
    Object.const_defined?(class_s(formula_name))
  end

  def self.get_formula_class formula_name
    Object.const_get(class_s(formula_name))
  end

  def self.restore_formula formula_name, value
    old_verbose, $VERBOSE = $VERBOSE, nil
    Object.const_set(class_s(formula_name), value)
  ensure
    $VERBOSE = old_verbose
  end

  def self.class_s name
    (@class_s ||= {}).fetch(name) do
      class_name = name.capitalize
      class_name.gsub!(/[-_.\s]([a-zA-Z0-9])/) { $1.upcase }
      class_name.gsub!('+', 'x')
      @class_s[name] = class_name
    end
  end

  # A FormulaLoader returns instances of formulae.
  # Subclasses implement loaders for particular sources of formulae.
  class FormulaLoader
    # The formula's name
    attr_reader :name
    # The formula's ruby file's path or filename
    attr_reader :path

    # Gets the formula instance.
    # Subclasses must define this.
    def get_formula; end

    # Return the Class for this formula, `require`-ing it if
    # it has not been parsed before.
    def klass
      begin
        have_klass = Formulary.formula_class_defined? name
      rescue NameError
        raise FormulaUnavailableError.new(name)
      end

      unless have_klass
        puts "#{$0}: loading #{path}" if ARGV.debug?
        begin
          require path
        rescue NoMethodError
          # This is a programming error in an existing formula, and should not
          # have a "no such formula" message.
          raise
        rescue LoadError, NameError
          raise if ARGV.debug?  # let's see the REAL error
          raise FormulaUnavailableError.new(name)
        end
      end

      klass = Formulary.get_formula_class(name)
      if klass == Formula || !(klass < Formula)
        raise FormulaUnavailableError.new(name)
      end
      klass
    end
  end

  # Loads formulae from bottles.
  class BottleLoader < FormulaLoader
    def initialize bottle_name
      @bottle_filename = Pathname(bottle_name).realpath
      name_without_version = bottle_filename_formula_name @bottle_filename
      if name_without_version.empty?
        if ARGV.homebrew_developer?
          opoo "Add a new regex to bottle_version.rb to parse this filename."
        end
        @name = bottle_name
      else
        @name = name_without_version
      end
      @path = Formula.path(@name)
    end

    def get_formula
      formula = klass.new(name, path)
      formula.local_bottle_path = @bottle_filename
      return formula
    end
  end

  # Loads formulae from Homebrew's provided Library
  class StandardLoader < FormulaLoader
    def initialize name
      @name = name
      @path = Formula.path(name)
    end

    def get_formula
      klass.new(name, path)
    end
  end

  # Loads formulae from disk using a path
  class FromPathLoader < FormulaLoader
    def initialize path
      # require allows filenames to drop the .rb extension, but everything else
      # in our codebase will require an exact and fullpath.
      path = "#{path}.rb" unless path =~ /\.rb$/

      @path = Pathname.new(path).expand_path
      @name = @path.stem
    end

    def get_formula
      klass.new(name, path)
    end
  end

  # Loads formulae from URLs
  class FromUrlLoader < FormulaLoader
    attr_reader :url

    def initialize url
      @url = url
      @path = HOMEBREW_CACHE_FORMULA/File.basename(url)
      @name = File.basename(url, '.rb')
    end

    # Downloads the formula's .rb file
    def fetch
      unless Formulary.formula_class_defined? name
        HOMEBREW_CACHE_FORMULA.mkpath
        FileUtils.rm path.to_s, :force => true
        curl url, '-o', path.to_s
      end
    end

    def get_formula
      return klass.new(name, path)
    end
  end

  # Loads tapped formulae.
  class TapLoader < FormulaLoader
    def initialize tapped_name
      @name = tapped_name
      @path = Pathname.new(tapped_name)
    end

    def get_formula
      klass.new(tapped_name, path)
    end
  end

  # Return a Formula instance for the given reference.
  # `ref` is string containing:
  # * a formula name
  # * a formula pathname
  # * a formula URL
  # * a local bottle reference
  def self.factory ref
    # If a URL is passed, download to the cache and install
    if ref =~ %r[(https?|ftp)://]
      f = FromUrlLoader.new(ref)
      f.fetch
    elsif ref =~ Pathname::BOTTLE_EXTNAME_RX
      f = BottleLoader.new(ref)
    else
      name_or_path = Formula.canonical_name(ref)
      if name_or_path =~ %r{^(\w+)/(\w+)/([^/])+$}
        # name appears to be a tapped formula, so we don't munge it
        # in order to provide a useful error message when require fails.
        f = TapLoader.new(name_or_path)
      elsif name_or_path.include? "/"
        # If name was a path or mapped to a cached formula
        f = FromPathLoader.new(name_or_path)
      elsif name_or_path =~ /\.rb$/
        f = FromPathLoader.new("./#{name_or_path}")
      else
        f = StandardLoader.new(name_or_path)
      end
    end

    f.get_formula
  end
end
