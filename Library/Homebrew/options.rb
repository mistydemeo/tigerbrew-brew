require 'set'

class Option
  include Comparable

  attr_reader :name, :description, :flag

  def initialize(name, description=nil)
    @name, @flag = split_name(name)
    @description = description.to_s
  end

  def to_s
    flag
  end
  alias_method :to_str, :to_s

  def to_json
    flag.inspect
  end

  def <=>(other)
    name <=> other.name
  end

  def eql?(other)
    other.is_a?(self.class) && hash == other.hash
  end

  def hash
    name.hash
  end

  private

  def split_name(name)
    case name
    when /^[a-zA-Z]$/
      [name, "-#{name}"]
    when /^-[a-zA-Z]$/
      [name[1..1], name]
    when /^--(.+)$/
      [$1, name]
    else
      [name, "--#{name}"]
    end
  end
end

class Options
  include Enumerable

  def initialize(*args)
    @options = Set.new(*args)
  end

  def each(*args, &block)
    @options.each(*args, &block)
  end

  def <<(o)
    @options << o
    self
  end

  def +(o)
    Options.new(@options + o)
  end

  def -(o)
    Options.new(@options - o)
  end

  def &(o)
    Options.new(@options & o)
  end

  def *(arg)
    @options.to_a * arg
  end

  def empty?
    @options.empty?
  end

  def as_flags
    map(&:flag)
  end

  def include?(o)
    any? { |opt| opt == o || opt.name == o || opt.flag == o }
  end

  def concat(o)
    o.each { |opt| @options << opt }
    self
  end

  def to_a
    @options.to_a
  end
  alias_method :to_ary, :to_a

  def self.coerce(arg)
    case arg
    when self then arg
    when Option then new << arg
    when Array
      opts = arg.map do |_arg|
        case _arg
        when /^-[^-]+$/ then _arg[1..-1].split(//)
        else _arg
        end
      end.flatten
      new(opts.map { |o| Option.new(o) })
    else
      raise TypeError, "Cannot convert #{arg.inspect} to Options"
    end
  end
end
