module InstallRenamed
  def install_p src, new_basename = nil
    super do |src, dst|
      dst += "/#{File.basename(src)}" if File.directory? dst
      append_default_if_different(src, dst)
    end
  end

  def cp_path_sub pattern, replacement
    super do |src, dst|
      append_default_if_different(src, dst)
    end
  end

  private

  def append_default_if_different src, dst
    if File.file? dst and !FileUtils.identical?(src, dst) and !ENV['HOMEBREW_GIT_ETC']
      dst += ".default"
    end
    dst
  end
end
