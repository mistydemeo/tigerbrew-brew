# Cleans a newly installed keg.
# By default:
# * removes .la files
# * removes empty directories
# * sets permissions on executables
# * removes unresolved symlinks
class Cleaner

  # Create a cleaner for the given formula
  def initialize f
    @f = f
  end

  # Clean the keg of formula @f
  def clean
    ObserverPathnameExtension.reset_counts!

    # Many formulae include 'lib/charset.alias', but it is not strictly needed
    # and will conflict if more than one formula provides it
    alias_path = @f.lib/'charset.alias'
    alias_path.extend(ObserverPathnameExtension).unlink if alias_path.exist?

    [@f.bin, @f.sbin, @f.lib].select{ |d| d.exist? }.each{ |d| clean_dir d }

    # Get rid of any info 'dir' files, so they don't conflict at the link stage
    info_dir_file = @f.info + 'dir'
    if info_dir_file.file? and not @f.skip_clean? info_dir_file
      puts "rm #{info_dir_file}" if ARGV.verbose?
      info_dir_file.unlink
    end

    prune
  end

  private

  # Removes any empty directories in the formula's prefix subtree
  # Keeps any empty directions projected by skip_clean
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

    # Remove directories opposite from traversal, so that a subtree with no
    # actual files gets removed correctly.
    dirs.reverse_each do |d|
      if d.children.empty?
        puts "rmdir: #{d} (empty)" if ARGV.verbose?
        d.rmdir
      end
    end

    # Remove unresolved symlinks
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

  # Removes .la files and fixes file permissions for a directory tree, keeping
  # existing files and permissions if instructed to by the formula
  def clean_dir d
    d.find do |path|
      path.extend(ObserverPathnameExtension)

      Find.prune if @f.skip_clean? path

      if path.symlink? or path.directory?
        next
      elsif path.extname == '.la'
        path.unlink
      else
        clean_file_permissions(path)
      end
    end
  end

end
