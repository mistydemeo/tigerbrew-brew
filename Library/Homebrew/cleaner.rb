# Cleans a newly installed keg.
# By default:
# * removes info files
# * removes .la files
# * removes empty directories
# * sets permissions on executables
class Cleaner

  # Create a cleaner for the given formula and clean its keg
  def initialize f
    ObserverPathnameExtension.reset_counts!

    @f = f
    [f.bin, f.sbin, f.lib].select{ |d| d.exist? }.each{ |d| clean_dir d }

    if ENV['HOMEBREW_KEEP_INFO']
      # Get rid of the directory file, so it no longer bother us at link stage.
      info_dir_file = f.info + 'dir'
      if info_dir_file.file? and not f.skip_clean? info_dir_file
        puts "rm #{info_dir_file}" if ARGV.verbose?
        info_dir_file.unlink
      end
    else
      f.info.rmtree if f.info.directory? and not f.skip_clean? f.info
    end

    prune
  end

  private

  def prune
    dirs = []
    symlinks = []

    @f.prefix.find do |path|
      if @f.skip_clean? path
        Find.prune
      elsif path.symlink?
        symlinks << path
      elsif path.directory?
        dirs << path
      end
    end

    dirs.reverse_each do |d|
      if d.children.empty?
        puts "rmdir: #{d} (empty)" if ARGV.verbose?
        d.rmdir
      end
    end

    symlinks.reverse_each do |s|
      s.unlink unless s.resolved_path_exists?
    end
  end

  # Set permissions for executables and non-executables
  def clean_file_permissions path
    perms = if path.mach_o_executable? || path.text_executable?
      0555
    else
      0444
    end
    if ARGV.debug?
      old_perms = path.stat.mode & 0777
      if perms != old_perms
        puts "Fixing #{path} permissions from #{old_perms.to_s(8)} to #{perms.to_s(8)}"
      end
    end
    path.chmod perms
  end

  # Clean a single folder (non-recursively)
  def clean_dir d
    d.find do |path|
      path.extend(ObserverPathnameExtension)

      Find.prune if @f.skip_clean? path

      if path.symlink? or path.directory?
        next
      elsif path.extname == '.la'
        path.unlink
      elsif path == @f.lib+'charset.alias'
        # Many formulae symlink this file, but it is not strictly needed
        path.unlink
      else
        clean_file_permissions(path)
      end
    end
  end

end
