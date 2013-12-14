class Compiler < Struct.new(:name, :priority)
  # The full version of the compiler for comparison purposes.
  def version
    if name.is_a? String
      MacOS.non_apple_gcc_version(name)
    else
      MacOS.send("#{name}_build_version")
    end
  end

  # This is exposed under the `build` name for compatibility, since
  # `fails_with` continues to use `build` in the public API.
  # `build` indicates the build number of an Apple compiler.
  # This is preferred over version numbers since there are often
  # significant differences within the same version,
  # e.g. GCC 4.2 build 5553 vs 5666.
  # Non-Apple compilers don't have build numbers.
  alias_method :build, :version

  # The major version for non-Apple compilers. Used to indicate a compiler
  # series; for instance, if the version is 4.8.2, it would return "4.8".
  def major_version
    version.match(/(\d\.\d)/)[0] if name.is_a? String
  end
end

class CompilerFailure
  attr_reader :compiler, :major_version
  attr_rw :cause, :version

  def initialize compiler, &block
    # Non-Apple compilers are in the format fails_with compiler => version
    if compiler.is_a? Hash
      # currently the only compiler for this case is GCC
      _, @major_version = compiler.shift
      @compiler = 'gcc-' + @major_version
    else
      @compiler = compiler
    end

    instance_eval(&block) if block_given?

    if compiler.is_a? Hash
      # so fails_with :gcc => '4.8' simply marks all 4.8 releases incompatible
      @version ||= @major_version + '.999'
    else
      @version = (@version || 9999).to_i
    end
  end

  # Allows Apple compiler `fails_with` statements to keep using `build`
  # even though `build` and `value` are the same internally
  alias_method :build, :version
end

class CompilerQueue
  def initialize
    @array = []
  end

  def <<(o)
    @array << o
    self
  end

  def pop
    @array.delete(@array.max { |a, b| a.priority <=> b.priority })
  end

  def empty?
    @array.empty?
  end
end

class CompilerSelector
  def initialize(f)
    @f = f
    @compilers = CompilerQueue.new
    %w{clang llvm gcc gcc_4_0}.map(&:to_sym).each do |cc|
      unless MacOS.send("#{cc}_build_version").nil?
        @compilers << Compiler.new(cc, priority_for(cc))
      end
    end

    # non-Apple GCC 4.x
    SharedEnvExtension::GNU_GCC_VERSIONS.each do |v|
      unless MacOS.non_apple_gcc_version("gcc-4.#{v}").nil?
        # priority is based on version, with newest preferred first
        @compilers << Compiler.new("gcc-4.#{v}", 1.0 + v/10.0)
      end
    end
  end

  # Attempts to select an appropriate alternate compiler, but
  # if none can be found raises CompilerError instead
  def compiler
    begin
      cc = @compilers.pop
    end while @f.fails_with?(cc)

    if cc.nil?
      raise CompilerSelectionError.new(@f)
    else
      cc.name
    end
  end

  private

  def priority_for(cc)
    case cc
    when :clang then MacOS.clang_build_version >= 318 ? 3 : 0.5
    when :gcc   then 2.5
    when :llvm  then 2
    when :gcc_4_0 then 0.25
    # non-Apple gcc compilers
    else 1.5
    end
  end
end
