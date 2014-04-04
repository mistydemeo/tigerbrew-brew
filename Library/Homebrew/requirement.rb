require 'dependable'
require 'dependency'
require 'build_environment'
require 'extend/ENV'

# A base class for non-formula requirements needed by formulae.
# A "fatal" requirement is one that will fail the build if it is not present.
# By default, Requirements are non-fatal.
class Requirement
  include Dependable
  extend BuildEnvironmentDSL

  attr_reader :tags, :name, :option_name

  def initialize(tags=[])
    @tags = tags
    @tags << :build if self.class.build
    @name ||= infer_name
    @option_name = @name
  end

  # The message to show when the requirement is not met.
  def message; "" end

  # Overriding #satisfied? is deprecated.
  # Pass a block or boolean to the satisfy DSL method instead.
  def satisfied?
    result = self.class.satisfy.yielder do |proc|
      instance_eval(&proc)
    end

    infer_env_modification(result)
    !!result
  end

  # Can overridden to optionally prevent a formula with this requirement from
  # pouring a bottle.
  def pour_bottle?; true end

  # Overriding #fatal? is deprecated.
  # Pass a boolean to the fatal DSL method instead.
  def fatal?
    self.class.fatal || false
  end

  def default_formula?
    self.class.default_formula || false
  end

  # Overriding #modify_build_environment is deprecated.
  # Pass a block to the the env DSL method instead.
  # Note: #satisfied? should be called before invoking this method
  # as the env modifications may depend on its side effects.
  def modify_build_environment
    env.modify_build_environment(self)
  end

  def env
    @env ||= self.class.env
  end

  def eql?(other)
    instance_of?(other.class) && name == other.name && tags == other.tags
  end

  def hash
    [name, *tags].hash
  end

  def inspect
    "#<#{self.class}: #{name.inspect} #{tags.inspect}>"
  end

  def to_dependency
    f = self.class.default_formula
    raise "No default formula defined for #{inspect}" if f.nil?
    Dependency.new(f, tags, method(:modify_build_environment), name)
  end

  private

  def infer_name
    klass = self.class.to_s
    klass.sub!(/(Dependency|Requirement)$/, '')
    klass.sub!(/^(\w+::)*/, '')
    klass.downcase
  end

  def infer_env_modification(o)
    case o
    when Pathname
      self.class.env do
        unless ENV["PATH"].split(File::PATH_SEPARATOR).include?(o.parent.to_s)
          ENV.append_path("PATH", o.parent)
        end
      end
    end
  end

  def which(cmd)
    super(cmd, ORIGINAL_PATHS.join(File::PATH_SEPARATOR))
  end

  class << self
    attr_rw :fatal, :build, :default_formula

    def satisfy(options={}, &block)
      @satisfied ||= Requirement::Satisfier.new(options, &block)
    end
  end

  class Satisfier
    def initialize(options={}, &block)
      case options
      when Hash
        @options = { :build_env => true }
        @options.merge!(options)
      else
        @satisfied = options
      end
      @proc = block
    end

    def yielder
      if instance_variable_defined?(:@satisfied)
        @satisfied
      elsif @options[:build_env]
        ENV.with_build_environment { yield @proc }
      else
        yield @proc
      end
    end
  end

  class << self
    # Expand the requirements of dependent recursively, optionally yielding
    # [dependent, req] pairs to allow callers to apply arbitrary filters to
    # the list.
    # The default filter, which is applied when a block is not given, omits
    # optionals and recommendeds based on what the dependent has asked for.
    def expand(dependent, &block)
      reqs = ComparableSet.new

      formulae = dependent.recursive_dependencies.map(&:to_formula)
      formulae.unshift(dependent)

      formulae.each do |f|
        f.requirements.each do |req|
          if prune?(f, req, &block)
            next
          else
            reqs << req
          end
        end
      end

      reqs
    end

    def prune?(dependent, req, &block)
      catch(:prune) do
        if block_given?
          yield dependent, req
        elsif req.optional? || req.recommended?
          prune unless dependent.build.with?(req)
        end
      end
    end

    # Used to prune requirements when calling expand with a block.
    def prune
      throw(:prune, true)
    end
  end
end
