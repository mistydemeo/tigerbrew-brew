require "cmd/tap"
require "formula_versions"

module Homebrew
  def update
    unless ARGV.named.empty?
      abort <<-EOS.undent
        This command updates brew itself, and does not take formula names.
        Use `brew upgrade <formula>`.
      EOS
    end

    # ensure GIT_CONFIG is unset as we need to operate on .git/config
    ENV.delete('GIT_CONFIG')

    cd HOMEBREW_REPOSITORY
    git_init_if_necessary

    # migrate to new directories based tap structure
    migrate_taps

    report = Report.new
    master_updater = Updater.new(HOMEBREW_REPOSITORY)
    master_updater.pull!
    report.update(master_updater.report)

    # rename Taps directories
    # this procedure will be removed in the future if it seems unnecessasry
    rename_taps_dir_if_necessary

    Tap.each do |tap|
      tap.path.cd do
        updater = Updater.new(tap.path)

        begin
          updater.pull!
        rescue
          onoe "Failed to update tap: #{tap}"
        else
          report.update(updater.report) do |key, oldval, newval|
            oldval.concat(newval)
          end
        end
      end
    end

    # automatically tap any migrated formulae's new tap
    report.select_formula(:D).each do |f|
      next unless (HOMEBREW_CELLAR/f).exist?
      migration = TAP_MIGRATIONS[f]
      next unless migration
      tap_user, tap_repo = migration.split '/'
      install_tap tap_user, tap_repo
    end if load_tap_migrations

    if report.empty?
      puts "Already up-to-date."
    else
      puts "Updated Tigerbrew from #{master_updater.initial_revision[0,8]} to #{master_updater.current_revision[0,8]}."
      report.dump
    end
  end

  private

  def git_init_if_necessary
    if Dir[".git/*"].empty?
      safe_system "git", "init"
      safe_system "git", "config", "core.autocrlf", "false"
      safe_system "git", "config", "remote.origin.url", "https://github.com/mistydemeo/tigerbrew.git"
      safe_system "git", "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"
      safe_system "git", "fetch", "origin"
      safe_system "git", "reset", "--hard", "origin/master"
    end

    if `git remote show origin -n` =~ /Fetch URL: \S+mxcl\/homebrew/
      safe_system "git", "remote", "set-url", "origin", "https://github.com/Homebrew/homebrew.git"
      safe_system "git", "remote", "set-url", "--delete", "origin", ".*mxcl\/homebrew.*"
    end
  rescue Exception
    FileUtils.rm_rf ".git"
    raise
  end

  def rename_taps_dir_if_necessary
    Dir.glob("#{HOMEBREW_LIBRARY}/Taps/*/") do |tapd|
      begin
        tapd_basename = File.basename(tapd)

        if File.directory?(tapd + "/.git")
          if tapd_basename.include?("-")
            # only replace the *last* dash: yes, tap filenames suck
            user, repo = tapd_basename.reverse.sub("-", "/").reverse.split("/")

            FileUtils.mkdir_p("#{HOMEBREW_LIBRARY}/Taps/#{user.downcase}")
            FileUtils.mv(tapd, "#{HOMEBREW_LIBRARY}/Taps/#{user.downcase}/homebrew-#{repo.downcase}")

            if tapd_basename.count("-") >= 2
              opoo "Tigerbrew changed the structure of Taps like <someuser>/<sometap>. "\
                + "So you may need to rename #{HOMEBREW_LIBRARY}/Taps/#{user.downcase}/homebrew-#{repo.downcase} manually."
            end
          else
            opoo "Tigerbrew changed the structure of Taps like <someuser>/<sometap>. "\
              "#{tapd} is incorrect name format. You may need to rename it like <someuser>/<sometap> manually."
          end
        end
      rescue => ex
        onoe ex.message
        next # next tap directory
      end
    end
  end

  def load_tap_migrations
    require 'tap_migrations'
  rescue LoadError
    false
  end
end

class Updater
  attr_reader :initial_revision, :current_revision, :repository

  def initialize(repository)
    @repository = repository
  end

  def pull!
    safe_system "git", "checkout", "-q", "master"

    @initial_revision = read_current_revision

    # ensure we don't munge line endings on checkout
    safe_system "git", "config", "core.autocrlf", "false"

    args = ["pull"]
    args << "--rebase" if ARGV.include? "--rebase"
    args << "-q" unless ARGV.verbose?
    args << "origin"
    # the refspec ensures that 'origin/master' gets updated
    args << "refs/heads/master:refs/remotes/origin/master"

    reset_on_interrupt { safe_system "git", *args }

    @current_revision = read_current_revision
  end

  def reset_on_interrupt
    ignore_interrupts { yield }
  ensure
    if $?.signaled? && $?.termsig == 2 # SIGINT
      safe_system "git", "reset", "--hard", @initial_revision
    end
  end

  def report
    map = Hash.new{ |h,k| h[k] = [] }

    if initial_revision && initial_revision != current_revision
      diff.each_line do |line|
        status, *paths = line.split
        src, dst = paths.first, paths.last

        next unless File.extname(dst) == ".rb"
        next unless paths.any? { |p| File.dirname(p) == formula_directory }

        case status
        when "A", "D"
          map[status.to_sym] << repository.join(src)
        when "M"
          file = repository.join(src)
          begin
            formula = Formulary.factory(file)
            new_version = formula.pkg_version
            old_version = FormulaVersions.new(formula).formula_at_revision(@initial_revision, &:pkg_version)
            next if new_version == old_version
          rescue LoadError, FormulaUnavailableError => e
            onoe e if ARGV.homebrew_developer?
          end
          map[:M] << file
        when /^R\d{0,3}/
          map[:D] << repository.join(src) if File.dirname(src) == formula_directory
          map[:A] << repository.join(dst) if File.dirname(dst) == formula_directory
        end
      end
    end

    map
  end

  private

  def formula_directory
    if repository == HOMEBREW_REPOSITORY
      "Library/Formula"
    elsif repository.join("Formula").directory?
      "Formula"
    elsif repository.join("HomebrewFormula").directory?
      "HomebrewFormula"
    else
      "."
    end
  end

  def read_current_revision
    `git rev-parse -q --verify HEAD`.chomp
  end

  def diff
    Utils.popen_read(
      "git", "diff-tree", "-r", "--name-status", "--diff-filter=AMDR",
      "-M85%", initial_revision, current_revision
    )
  end

  def `(cmd)
    out = super
    unless $?.success?
      $stderr.puts(out) unless out.empty?
      raise ErrorDuringExecution.new(cmd)
    end
    ohai(cmd, out) if ARGV.verbose?
    out
  end
end


class Report
  def initialize
    @hash = {}
  end

  def fetch(*args, &block)
    @hash.fetch(*args, &block)
  end

  def update(*args, &block)
    @hash.update(*args, &block)
  end

  def empty?
    @hash.empty?
  end

  def dump
    # Key Legend: Added (A), Copied (C), Deleted (D), Modified (M), Renamed (R)

    dump_formula_report :A, "New Formulae"
    dump_formula_report :M, "Updated Formulae"
    dump_formula_report :D, "Deleted Formulae"
  end

  def select_formula key
    fetch(key, []).map do |path|
      case path.to_s
      when HOMEBREW_TAP_PATH_REGEX
        "#{$1}/#{$2.sub("homebrew-", "")}/#{path.basename(".rb")}"
      else
        path.basename(".rb").to_s
      end
    end.sort
  end

  def dump_formula_report key, title
    formula = select_formula(key)
    unless formula.empty?
      ohai title
      puts_columns formula
    end
  end
end
