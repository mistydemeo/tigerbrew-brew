require 'pathname'
require 'mach'
require 'resource'

# we enhance pathname to make our code more readable
class Pathname
  include MachO

  BOTTLE_EXTNAME_RX = /(\.[a-z_]+(32)?\.bottle\.(\d+\.)?tar\.gz)$/

  def install *sources
    sources.each do |src|
      case src
      when Resource
        src.stage(self)
      when Resource::Partial
        src.resource.stage { install(*src.files) }
      when Array
        if src.empty?
          opoo "tried to install empty array to #{self}"
          return
        end
        src.each {|s| install_p(s) }
      when Hash
        if src.empty?
          opoo "tried to install empty hash to #{self}"
          return
        end
        src.each {|s, new_basename| install_p(s, new_basename) }
      else
        install_p(src)
      end
    end
  end

  def install_p src, new_basename = nil
    if new_basename
      new_basename = File.basename(new_basename) # rationale: see Pathname.+
      dst = self+new_basename
    else
      dst = self
    end

    src = src.to_s
    dst = dst.to_s

    # if it's a symlink, don't resolve it to a file because if we are moving
    # files one by one, it's likely we will break the symlink by moving what
    # it points to before we move it
    # and also broken symlinks are not the end of the world
    raise "#{src} does not exist" unless File.symlink? src or File.exist? src

    dst = yield(src, dst) if block_given?

    mkpath
    if File.symlink? src
      # we use the BSD mv command because FileUtils copies the target and
      # not the link! I'm beginning to wish I'd used Python quite honestly!
      raise unless Kernel.system 'mv', src, dst
    else
      # we mv when possible as it is faster and you should only be using
      # this function when installing from the temporary build directory
      FileUtils.mv src, dst
    end
  end
  protected :install_p

  # Creates symlinks to sources in this folder.
  def install_symlink *sources
    sources.each do |src|
      case src
      when Array
        src.each {|s| install_symlink_p(s) }
      when Hash
        src.each {|s, new_basename| install_symlink_p(s, new_basename) }
      else
        install_symlink_p(src)
      end
    end
  end

  def install_symlink_p src, new_basename=src
    src = Pathname(src).expand_path(self)
    dst = join File.basename(new_basename)
    mkpath
    FileUtils.ln_s src.relative_path_from(dst.parent), dst
  end
  protected :install_symlink_p

  # we assume this pathname object is a file obviously
  def write content
    raise "Will not overwrite #{to_s}" if exist?
    dirname.mkpath
    File.open(self, 'w') {|f| f.write content }
  end

  # NOTE always overwrites
  def atomic_write content
    require "tempfile"
    tf = Tempfile.new(basename.to_s)
    tf.binmode
    tf.write(content)
    tf.close

    begin
      old_stat = stat
    rescue Errno::ENOENT
      old_stat = default_stat
    end

    FileUtils.mv tf.path, self

    uid = Process.uid
    gid = Process.groups.delete(old_stat.gid) { Process.gid }

    begin
      chown(uid, gid)
      chmod(old_stat.mode)
    rescue Errno::EPERM
    end
  end

  def default_stat
    sentinel = parent.join(".brew.#{Process.pid}.#{rand(Time.now.to_i)}")
    sentinel.open("w") { }
    sentinel.stat
  ensure
    sentinel.unlink
  end
  private :default_stat

  def cp dst
    if file?
      FileUtils.cp to_s, dst
    else
      FileUtils.cp_r to_s, dst
    end
    return dst
  end

  def cp_path_sub pattern, replacement
    raise "#{self} does not exist" unless self.exist?

    src = self.to_s
    dst = src.sub(pattern, replacement)
    raise "#{src} is the same file as #{dst}" if src == dst

    dst_path = Pathname.new dst

    if self.directory?
      dst_path.mkpath
      return
    end

    dst_path.dirname.mkpath

    dst = yield(src, dst) if block_given?

    FileUtils.cp(src, dst)
  end

  # extended to support common double extensions
  alias extname_old extname
  def extname(path=to_s)
    BOTTLE_EXTNAME_RX.match(path)
    return $1 if $1
    /(\.(tar|cpio|pax)\.(gz|bz2|lz|xz|Z))$/.match(path)
    return $1 if $1
    return File.extname(path)
  end

  # for filetypes we support, basename without extension
  def stem
    File.basename((path = to_s), extname(path))
  end

  # I don't trust the children.length == 0 check particularly, not to mention
  # it is slow to enumerate the whole directory just to see if it is empty,
  # instead rely on good ol' libc and the filesystem
  def rmdir_if_possible
    rmdir
    true
  rescue Errno::ENOTEMPTY
    if (ds_store = self+'.DS_Store').exist? && children.length == 1
      ds_store.unlink
      retry
    else
      false
    end
  rescue Errno::EACCES, Errno::ENOENT
    false
  end

  def chmod_R perms
    require 'fileutils'
    FileUtils.chmod_R perms, to_s
  end

  def version
    require 'version'
    Version.parse(self)
  end

  def compression_type
    # Don't treat jars or wars as compressed
    return nil if self.extname == '.jar'
    return nil if self.extname == '.war'

    # OS X installer package
    return :pkg if self.extname == '.pkg'

    # If the filename ends with .gz not preceded by .tar
    # then we want to gunzip but not tar
    return :gzip_only if self.extname == '.gz'

    # Get enough of the file to detect common file types
    # POSIX tar magic has a 257 byte offset
    # magic numbers stolen from /usr/share/file/magic/
    case open('rb') { |f| f.read(262) }
    when /^PK\003\004/n         then :zip
    when /^\037\213/n           then :gzip
    when /^BZh/n                then :bzip2
    when /^\037\235/n           then :compress
    when /^.{257}ustar/n        then :tar
    when /^\xFD7zXZ\x00/n       then :xz
    when /^LZIP/n               then :lzip
    when /^Rar!/n               then :rar
    when /^7z\xBC\xAF\x27\x1C/n then :p7zip
    else
      # This code so that bad-tarballs and zips produce good error messages
      # when they don't unarchive properly.
      case extname
      when ".tar.gz", ".tgz", ".tar.bz2", ".tbz" then :tar
      when ".zip" then :zip
      end
    end
  end

  def text_executable?
    %r[^#!\s*\S+] === open('r') { |f| f.read(1024) }
  end

  def incremental_hash(hasher)
    incr_hash = hasher.new
    buf = ""
    open('rb') { |f| incr_hash << buf while f.read(1024, buf) }
    incr_hash.hexdigest
  end

  def sha1
    require 'digest/sha1'
    incremental_hash(Digest::SHA1)
  end

  def sha256
    if MacOS.version == :tiger
      openssl = Formula.factory('openssl')
      openssl_bin = openssl.opt_prefix/'bin/openssl'

      if !openssl.installed? || !(openssl_bin.exist? && `"#{openssl_bin}" dgst -h 2>&1` =~ /sha256/)
        raise "You must `brew install openssl` to compute sha256 hashes on Tiger"
      end
      str = `"#{openssl_bin}" dgst -sha256 "#{self}"`.chomp
      str.match(/= ((\d|[a-z])+)/).captures.first
    else
      require 'digest/sha2'
      incremental_hash(Digest::SHA2)
    end
  end

  def verify_checksum expected
    raise ChecksumMissingError if expected.nil? or expected.empty?
    actual = Checksum.new(expected.hash_type, send(expected.hash_type).downcase)
    raise ChecksumMismatchError.new(self, expected, actual) unless expected == actual
  end

  if '1.9' <= RUBY_VERSION
    alias_method :to_str, :to_s
  end

  def cd
    Dir.chdir(self){ yield }
  end

  def subdirs
    children.select{ |child| child.directory? }
  end

  def resolved_path
    self.symlink? ? dirname+readlink : self
  end

  def resolved_path_exists?
    link = readlink
  rescue ArgumentError
    # The link target contains NUL bytes
    false
  else
    (dirname+link).exist?
  end

  # perhaps confusingly, this Pathname object becomes the symlink pointing to
  # the src paramter.
  def make_relative_symlink src
    dirname.mkpath

    dirname.cd do
      # NOTE only system ln -s will create RELATIVE symlinks
      return if quiet_system("ln", "-s", src.relative_path_from(dirname), basename)
    end

    if symlink? && exist?
      raise <<-EOS.undent
        Could not symlink file: #{src}
        Target #{self} already exists as a symlink to #{readlink}.
        If this file is from another formula, you may need to
        `brew unlink` it. Otherwise, you may want to delete it.
        To force the link and overwrite all other conflicting files, do:
          brew link --overwrite formula_name

        To list all files that would be deleted:
          brew link --overwrite --dry-run formula_name
        EOS
    elsif exist?
      raise <<-EOS.undent
        Could not symlink file: #{src}
        Target #{self} already exists. You may need to delete it.
        To force the link and overwrite all other conflicting files, do:
          brew link --overwrite formula_name

        To list all files that would be deleted:
          brew link --overwrite --dry-run formula_name
        EOS
    elsif symlink?
      unlink
      make_relative_symlink(src)
    elsif !dirname.writable_real?
      raise <<-EOS.undent
        Could not symlink file: #{src}
        #{dirname} is not writable. You should change its permissions.
        EOS
    else
      raise <<-EOS.undent
        Could not symlink file: #{src}
        #{self} may already exist.
        #{dirname} may not be writable.
        EOS
    end
  end

  def / that
    join that.to_s
  end

  def ensure_writable
    saved_perms = nil
    unless writable_real?
      saved_perms = stat.mode
      chmod 0644
    end
    yield
  ensure
    chmod saved_perms if saved_perms
  end

  def install_info
    unless self.symlink?
      raise "Cannot install info entry for unbrewed info file '#{self}'"
    end
    system '/usr/bin/install-info', '--quiet', self.to_s, (self.dirname+'dir').to_s
  end

  def uninstall_info
    unless self.symlink?
      raise "Cannot uninstall info entry for unbrewed info file '#{self}'"
    end
    system '/usr/bin/install-info', '--delete', '--quiet', self.to_s, (self.dirname+'dir').to_s
  end

  def find_formula
    [self/:Formula, self/:HomebrewFormula, self].each do |d|
      if d.exist?
        d.children.map{ |child| child.relative_path_from(self) }.each do |pn|
          yield pn if pn.to_s =~ /.rb$/
        end
        break
      end
    end
  end

  # Writes an exec script in this folder for each target pathname
  def write_exec_script *targets
    targets.flatten!
    if targets.empty?
      opoo "tried to write exec scripts to #{self} for an empty list of targets"
      return
    end
    targets.each do |target|
      target = Pathname.new(target) # allow pathnames or strings
      (self+target.basename()).write <<-EOS.undent
        #!/bin/bash
        exec "#{target}" "$@"
      EOS
      # +x here so this will work during post-install as well
      (self+target.basename()).chmod 0644
    end
  end

  # Writes an exec script that sets environment variables
  def write_env_script target, env
    env_export = ''
    env.each {|key, value| env_export += "#{key}=\"#{value}\" "}
    self.write <<-EOS.undent
    #!/bin/bash
    #{env_export}exec "#{target}" "$@"
    EOS
  end

  # Writes a wrapper env script and moves all files to the dst
  def env_script_all_files dst, env
    dst.mkpath
    Dir["#{self}/*"].each do |file|
      file = Pathname.new(file)
      dst.install_p file
      new_file = dst+file.basename
      file.write_env_script(new_file, env)
    end
  end

  # Writes an exec script that invokes a java jar
  def write_jar_script target_jar, script_name, java_opts=""
    (self+script_name).write <<-EOS.undent
      #!/bin/bash
      exec java #{java_opts} -jar #{target_jar} "$@"
    EOS
    # +x here so this will work during post-install as well
    (self+script_name).chmod 0644
  end

  def install_metafiles from=nil
    # Default to current path, and make sure we have a pathname, not a string
    from = "." if from.nil?
    from = Pathname.new(from.to_s)

    from.children.each do |p|
      next if p.directory?
      next unless FORMULA_META_FILES.should_copy? p
      # Some software symlinks these files (see help2man.rb)
      filename = p.resolved_path
      # Some software links metafiles together, so by the time we iterate to one of them
      # we may have already moved it. libxml2's COPYING and Copyright are affected by this.
      next unless filename.exist?
      filename.chmod 0644
      self.install filename
    end
  end

  def abv
    out=''
    n=`find #{to_s} -type f ! -name .DS_Store | wc -l`.to_i
    out<<"#{n} files, " if n > 1
    out<<`/usr/bin/du -hs #{to_s} | cut -d"\t" -f1`.strip
  end

  # We redefine these private methods in order to add the /o modifier to
  # the Regexp literals, which forces string interpolation to happen only
  # once instead of each time the method is called. This is fixed in 1.9+.
  if RUBY_VERSION <= "1.8.7" && RUBY_VERSION > "1.8.2"
    alias_method :old_chop_basename, :chop_basename
    def chop_basename(path)
      base = File.basename(path)
      if /\A#{Pathname::SEPARATOR_PAT}?\z/o =~ base
        return nil
      else
        return path[0, path.rindex(base)], base
      end
    end
    private :chop_basename

    alias_method :old_prepend_prefix, :prepend_prefix
    def prepend_prefix(prefix, relpath)
      if relpath.empty?
        File.dirname(prefix)
      elsif /#{SEPARATOR_PAT}/o =~ prefix
        prefix = File.dirname(prefix)
        prefix = File.join(prefix, "") if File.basename(prefix + 'a') != 'a'
        prefix + relpath
      else
        prefix + relpath
      end
    end
    private :prepend_prefix
  end

  # This seems absolutely insane. Tiger's ruby (1.8.2) deals with
  # symlinked directores in nonsense ways.
  # Pathname#unlink checks whether the target is a file or a directory,
  # and calls the appropriate File or Dir method as appropriate.
  # So far so good.
  # On the other hand, if the target is a) a directory, and b) a
  # symlink, then Pathname will redirect to Dir.unlink, which will
  # then treat the symlink as a *file* and raise Errno::EISDIR.
  if RUBY_VERSION <= "1.8.2"
    alias :oldunlink :unlink
    def unlink
      symlink? ? File.unlink(to_s) : oldunlink
    end
  end
end

module ObserverPathnameExtension
  class << self
    attr_accessor :n, :d

    def reset_counts!
      @n = @d = 0
    end

    def total
      n + d
    end

    def counts
      [n, d]
    end
  end

  def unlink
    super
    puts "rm #{to_s}" if ARGV.verbose?
    ObserverPathnameExtension.n += 1
  end
  def rmdir
    super
    puts "rmdir #{to_s}" if ARGV.verbose?
    ObserverPathnameExtension.d += 1
  end
  def make_relative_symlink src
    super
    ObserverPathnameExtension.n += 1
  end
  def install_info
    super
    puts "info #{to_s}" if ARGV.verbose?
  end
  def uninstall_info
    super
    puts "uninfo #{to_s}" if ARGV.verbose?
  end
end
