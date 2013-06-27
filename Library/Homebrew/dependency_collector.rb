require 'dependency'
require 'dependencies'
require 'requirement'
require 'requirements'
require 'requirements/ld64_dependency'
require 'set'

## A dependency is a formula that another formula needs to install.
## A requirement is something other than a formula that another formula
## needs to be present. This includes external language modules,
## command-line tools in the path, or any arbitrary predicate.
##
## The `depends_on` method in the formula DSL is used to declare
## dependencies and requirements.

# This class is used by `depends_on` in the formula DSL to turn dependency
# specifications into the proper kinds of dependencies and requirements.
class DependencyCollector
  # Define the languages that we can handle as external dependencies.
  LANGUAGE_MODULES = Set[
    :chicken, :jruby, :lua, :node, :ocaml, :perl, :python, :rbx, :ruby
  ].freeze

  attr_reader :deps, :requirements

  def initialize
    @deps = Dependencies.new
    @requirements = ComparableSet.new
  end

  def add(spec)
    case dep = build(spec)
    when Dependency
      @deps << dep
    when Requirement
      @requirements << dep
    when Array
      dep.each {|d| add(d)}
    end
    dep
  end

  def build(spec)
    spec, tags = case spec
                 when Hash then spec.shift
                 else spec
                 end

    parse_spec(spec, Array(tags))
  end

  private

  def parse_spec(spec, tags)
    case spec
    when String
      parse_string_spec(spec, tags)
    when Symbol
      parse_symbol_spec(spec, tags)
    when Requirement, Dependency
      spec
    when Class
      parse_class_spec(spec, tags)
    else
      raise TypeError, "Unsupported type #{spec.class} for #{spec.inspect}"
    end
  end

  def parse_string_spec(spec, tags)
    if tags.empty?
      Dependency.new(spec, tags)
    elsif (tag = tags.first) && LANGUAGE_MODULES.include?(tag)
      # Next line only for legacy support of `depends_on 'module' => :python`
      # It should be replaced by `depends_on :python => 'module'`
      return PythonInstalled.new("2", spec, *tags) if tag == :python
      LanguageModuleDependency.new(tag, spec)
    else
      Dependency.new(spec, tags)
    end
  end

  def parse_symbol_spec(spec, tags)
    case spec
    when :autoconf, :automake, :bsdmake, :libtool, :libltdl
      # Xcode no longer provides autotools or some other build tools
      autotools_dep(spec, tags)
    when :x11        then X11Dependency.new(spec.to_s, tags)
    when *X11Dependency::Proxy::PACKAGES
      x11_dep(spec, tags)
    when :cairo, :pixman
      # We no longer use X11 psuedo-deps for cairo or pixman,
      # so just return a standard formula dependency.
      Dependency.new(spec.to_s, tags)
    when :expat
      Dependency.new('expat', tags) if MacOS.version < :leopard
    when :x11        then X11Dependency.new(spec.to_s, tags)
    when :xcode      then XcodeDependency.new(tags)
    when :macos      then MinimumMacOSRequirement.new(tags)
    when :mysql      then MysqlDependency.new(tags)
    when :postgresql then PostgresqlDependency.new(tags)
    when :fortran    then FortranDependency.new(tags)
    when :mpi        then MPIDependency.new(*tags)
    when :tex        then TeXDependency.new(tags)
    when :clt        then CLTDependency.new(tags)
    when :arch       then ArchRequirement.new(tags)
    when :hg         then MercurialDependency.new(tags)
    when :python, :python2 then PythonInstalled.new("2", *tags)
    when :python3    then PythonInstalled.new("3", *tags)
    # Tiger's ld is too old to properly link some software
    when :ld64       then LD64Dependency.new if MacOS.version < :leopard
    else
      raise "Unsupported special dependency #{spec.inspect}"
    end
  end

  def parse_class_spec(spec, tags)
    if spec < Requirement
      spec.new(tags)
    else
      raise TypeError, "#{spec.inspect} is not a Requirement subclass"
    end
  end

  def x11_dep(spec, tags)
    # 10.8 doesn't come with X11, 10.4's X11 doesn't include these libs
    if MacOS.version >= :mountain_lion || MacOS.version < :leopard
      Dependency.new(spec.to_s, tags)
    else
      X11Dependency::Proxy.for(spec.to_s, tags)
    end
  end

  def autotools_dep(spec, tags)
    unless MacOS::Xcode.provides_autotools?
      case spec
      when :libltdl then spec = :libtool
      else tags << :build
      end

      Dependency.new(spec.to_s, tags)
    end
  end
end
