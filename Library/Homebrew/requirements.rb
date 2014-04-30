require 'requirement'
require 'requirements/fortran_dependency'
require 'requirements/language_module_dependency'
require 'requirements/minimum_macos_requirement'
require 'requirements/mpi_dependency'
require 'requirements/python_dependency'
require 'requirements/x11_dependency'

class XcodeDependency < Requirement
  fatal true
  build true

  satisfy(:build_env => false) { MacOS::Xcode.installed? }

  def message
    message = <<-EOS.undent
      A full installation of Xcode.app is required to compile this software.
      Installing just the Command Line Tools is not sufficient.
    EOS
    if MacOS.version >= :lion
      message += <<-EOS.undent
        Xcode can be installed from the App Store.
      EOS
    else
      message += <<-EOS.undent
        Xcode can be installed from https://developer.apple.com/downloads/
      EOS
    end
  end
end

class MysqlDependency < Requirement
  fatal true
  default_formula 'mysql'

  satisfy { which 'mysql_config' }
end

class PostgresqlDependency < Requirement
  fatal true
  default_formula 'postgresql'

  satisfy { which 'pg_config' }
end

class TeXDependency < Requirement
  fatal true

  satisfy { which('tex') || which('latex') }

  def message;
    if File.exist?("/usr/texbin")
      texbin_path = "/usr/texbin"
    else
      texbin_path = "its bin directory"
    end

    <<-EOS.undent
    A LaTeX distribution is required to install.

    You can install MacTeX distribution from:
      http://www.tug.org/mactex/

    Make sure that "/usr/texbin", or the location you installed it to, is in
    your PATH before proceeding.
    EOS
  end
end

class CLTDependency < Requirement
  fatal true
  build true

  satisfy(:build_env => false) { MacOS::CLT.installed? }

  def message
    message = <<-EOS.undent
      The Command Line Tools are required to compile this software.
    EOS
    if MacOS.version >= :mavericks
      message += <<-EOS.undent
        Run `xcode-select --install` to install them.
      EOS
    else
      message += <<-EOS.undent
        The standalone package can be obtained from
        https://developer.apple.com/downloads/,
        or it can be installed via Xcode's preferences.
      EOS
    end
  end
end

class ArchRequirement < Requirement
  fatal true

  def initialize(arch)
    @arch = arch.pop
    super
  end

  satisfy do
    case @arch
    when :x86_64 then MacOS.prefer_64_bit?
    when :intel, :ppc then Hardware::CPU.type == @arch
    end
  end

  def message
    "This formula requires an #{@arch} architecture."
  end
end

class MercurialDependency < Requirement
  fatal true
  default_formula 'mercurial'

  satisfy { which('hg') }
end

class GitDependency < Requirement
  fatal true
  default_formula 'git'
  satisfy { !!which('git') }
end
