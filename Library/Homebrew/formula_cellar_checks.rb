module FormulaCellarChecks
  def check_PATH bin
    # warn the user if stuff was installed outside of their PATH
    return unless bin.directory?
    return unless bin.children.length > 0

    prefix_bin = (HOMEBREW_PREFIX/bin.basename)
    return unless prefix_bin.directory?

    prefix_bin = prefix_bin.realpath
    return if ORIGINAL_PATHS.include? prefix_bin

    ["#{prefix_bin} is not in your PATH",
      "You can amend this by altering your ~/.bashrc file"]
  end

  def check_manpages
    # Check for man pages that aren't in share/man
    return unless (f.prefix+'man').directory?

    ['A top-level "man" directory was found.',
      <<-EOS.undent
        Tigerbrew requires that man pages live under share.
        This can often be fixed by passing "--mandir=\#{man}" to configure.
      EOS
    ]
  end

  def check_infopages
    # Check for info pages that aren't in share/info
    return unless (f.prefix+'info').directory?

    ['A top-level "info" directory was found.',
      <<-EOS.undent
        Tigerbrew suggests that info pages live under share.
        This can often be fixed by passing "--infodir=\#{info}" to configure.
      EOS
    ]
  end

  def check_jars
    return unless f.lib.directory?
    jars = f.lib.children.select { |g| g.extname == ".jar" }
    return if jars.empty?

    ["JARs were installed to \"#{f.lib}\".",
      <<-EOS.undent
        Installing JARs to "lib" can cause conflicts between packages.
        For Java software, it is typically better for the formula to
        install to "libexec" and then symlink or wrap binaries into "bin".
        See "activemq", "jruby", etc. for examples.
        The offending files are:
          #{jars * "\n          "}
      EOS
    ]
  end

  def check_non_libraries
    return unless f.lib.directory?

    valid_extensions = %w(.a .dylib .framework .jnilib .la .o .so
                          .jar .prl .pm .sh)
    non_libraries = f.lib.children.select do |g|
      next if g.directory?
      not valid_extensions.include? g.extname
    end
    return if non_libraries.empty?

    ["Non-libraries were installed to \"#{f.lib}\".",
      <<-EOS.undent
        Installing non-libraries to "lib" is discouraged.
        The offending files are:
          #{non_libraries * "\n          "}
      EOS
    ]
  end

  def check_non_executables bin
    return unless bin.directory?

    non_exes = bin.children.select { |g| g.directory? or not g.executable? }
    return if non_exes.empty?

    ["Non-executables were installed to \"#{bin}\".",
      <<-EOS.undent
        The offending files are:
          #{non_exes * "\n          "}
      EOS
    ]
  end

  def check_generic_executables bin
    return unless bin.directory?
    generic_names = %w[run service start stop]
    generics = bin.children.select { |g| generic_names.include? g.basename.to_s }
    return if generics.empty?

    ["Generic binaries were installed to \"#{bin}\".",
      <<-EOS.undent
        Binaries with generic names are likely to conflict with other software,
        and suggest that this software should be installed to "libexec" and
        then symlinked as needed.

        The offending files are:
          #{generics * "\n          "}
      EOS
    ]
  end
end
