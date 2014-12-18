module FormulaCellarChecks
  def check_PATH bin
    # warn the user if stuff was installed outside of their PATH
    return unless bin.directory?
    return unless bin.children.length > 0

    prefix_bin = (HOMEBREW_PREFIX/bin.basename)
    return unless prefix_bin.directory?

    prefix_bin = prefix_bin.realpath
    return if ORIGINAL_PATHS.include? prefix_bin

    <<-EOS.undent
      #{prefix_bin} is not in your PATH
      You can amend this by altering your ~/.bashrc file
    EOS
  end

  def check_manpages
    # Check for man pages that aren't in share/man
    return unless (formula.prefix+'man').directory?

    <<-EOS.undent
      A top-level "man" directory was found
      Tigerbrew requires that man pages live under share.
      This can often be fixed by passing "--mandir=\#{man}" to configure.
    EOS
  end

  def check_infopages
    # Check for info pages that aren't in share/info
    return unless (formula.prefix+'info').directory?

    <<-EOS.undent
      A top-level "info" directory was found
      Tigerbrew suggests that info pages live under share.
      This can often be fixed by passing "--infodir=\#{info}" to configure.
    EOS
  end

  def check_jars
    return unless formula.lib.directory?
    jars = formula.lib.children.select { |g| g.extname == ".jar" }
    return if jars.empty?

    <<-EOS.undent
      JARs were installed to "#{formula.lib}"
      Installing JARs to "lib" can cause conflicts between packages.
      For Java software, it is typically better for the formula to
      install to "libexec" and then symlink or wrap binaries into "bin".
      See "activemq", "jruby", etc. for examples.
      The offending files are:
        #{jars * "\n        "}
    EOS
  end

  def check_non_libraries
    return unless formula.lib.directory?

    valid_extensions = %w(.a .dylib .framework .jnilib .la .o .so
                          .jar .prl .pm .sh)
    non_libraries = formula.lib.children.select do |g|
      next if g.directory?
      not valid_extensions.include? g.extname
    end
    return if non_libraries.empty?

    <<-EOS.undent
      Non-libraries were installed to "#{formula.lib}"
      Installing non-libraries to "lib" is discouraged.
      The offending files are:
        #{non_libraries * "\n        "}
    EOS
  end

  def check_non_executables bin
    return unless bin.directory?

    non_exes = bin.children.select { |g| g.directory? or not g.executable? }
    return if non_exes.empty?

    <<-EOS.undent
      Non-executables were installed to "#{bin}"
      The offending files are:
        #{non_exes * "\n        "}
    EOS
  end

  def check_generic_executables bin
    return unless bin.directory?
    generic_names = %w[run service start stop]
    generics = bin.children.select { |g| generic_names.include? g.basename.to_s }
    return if generics.empty?

    <<-EOS.undent
      Generic binaries were installed to "#{bin}"
      Binaries with generic names are likely to conflict with other software,
      and suggest that this software should be installed to "libexec" and then
      symlinked as needed.

      The offending files are:
        #{generics * "\n        "}
    EOS
  end

  def check_shadowed_headers
    return if formula.name == "libtool" || formula.name == "subversion"
    return if formula.keg_only? || !formula.include.directory?

    files  = relative_glob(formula.include, "**/*.h")
    files &= relative_glob("#{MacOS.sdk_path}/usr/include", "**/*.h")
    files.map! { |p| File.join(formula.include, p) }

    return if files.empty?

    <<-EOS.undent
      Header files that shadow system header files were installed to "#{formula.include}"
      The offending files are:
        #{files * "\n        "}
    EOS
  end

  def check_easy_install_pth lib
    pth_found = Dir["#{lib}/python{2.7,3.4}/site-packages/easy-install.pth"].map { |f| File.dirname(f) }
    return if pth_found.empty?

    <<-EOS.undent
      easy-install.pth files were found
      These .pth files are likely to cause link conflicts. Please invoke
      setup.py with options
        --single-version-externally-managed --record=install.txt
      The offending files are
        #{pth_found * "\n        "}
    EOS
  end

  def check_openssl_links
    return unless formula.prefix.directory?
    keg = Keg.new(formula.prefix)
    system_openssl = keg.mach_o_files.select do |obj|
      dlls = obj.dynamically_linked_libraries
      dlls.any? { |dll| /\/usr\/lib\/lib(crypto|ssl).(\d\.)*dylib/.match dll }
    end
    return if system_openssl.empty?

    <<-EOS.undent
      object files were linked against system openssl
      These object files were linked against the deprecated system OpenSSL.
      Adding `depends_on "openssl"` to the formula may help.
        #{system_openssl  * "\n        "}
    EOS
  end

  def audit_installed
    audit_check_output(check_manpages)
    audit_check_output(check_infopages)
    audit_check_output(check_jars)
    audit_check_output(check_non_libraries)
    audit_check_output(check_non_executables(formula.bin))
    audit_check_output(check_generic_executables(formula.bin))
    audit_check_output(check_non_executables(formula.sbin))
    audit_check_output(check_generic_executables(formula.sbin))
    audit_check_output(check_shadowed_headers)
    audit_check_output(check_easy_install_pth(formula.lib))
    audit_check_output(check_openssl_links)
  end

  private

  def relative_glob(dir, pattern)
    File.directory?(dir) ? Dir.chdir(dir) { Dir[pattern] } : []
  end
end
