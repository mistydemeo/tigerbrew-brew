require 'pathname'
require 'exceptions'
require 'os/mac'
require 'utils/json'
require 'utils/inreplace'
require 'open-uri'

class Tty
  class << self
    def blue; bold 34; end
    def white; bold 39; end
    def red; underline 31; end
    def yellow; underline 33 ; end
    def reset; escape 0; end
    def em; underline 39; end
    def green; color 92 end
    def gray; bold 30 end

    def width
      `/usr/bin/tput cols`.strip.to_i
    end

    def truncate(str)
      str.to_s[0, width - 4]
    end

    private

    def color n
      escape "0;#{n}"
    end
    def bold n
      escape "1;#{n}"
    end
    def underline n
      escape "4;#{n}"
    end
    def escape n
      "\033[#{n}m" if $stdout.tty?
    end
  end
end

def ohai title, *sput
  title = Tty.truncate(title) if $stdout.tty? && !ARGV.verbose?
  puts "#{Tty.blue}==>#{Tty.white} #{title}#{Tty.reset}"
  puts sput unless sput.empty?
end

def oh1 title
  title = Tty.truncate(title) if $stdout.tty? && !ARGV.verbose?
  puts "#{Tty.green}==>#{Tty.white} #{title}#{Tty.reset}"
end

def opoo warning
  STDERR.puts "#{Tty.red}Warning#{Tty.reset}: #{warning}"
end

def onoe error
  lines = error.to_s.split("\n")
  STDERR.puts "#{Tty.red}Error#{Tty.reset}: #{lines.shift}"
  STDERR.puts lines unless lines.empty?
end

def ofail error
  onoe error
  Homebrew.failed = true
end

def odie error
  onoe error
  exit 1
end

def pretty_duration s
  return "2 seconds" if s < 3 # avoids the plural problem ;)
  return "#{s.to_i} seconds" if s < 120
  return "%.1f minutes" % (s/60)
end

def interactive_shell f=nil
  unless f.nil?
    ENV['HOMEBREW_DEBUG_PREFIX'] = f.prefix
    ENV['HOMEBREW_DEBUG_INSTALL'] = f.name
  end

  fork {exec ENV['SHELL'] }
  Process.wait
  unless $?.success?
    puts "Aborting due to non-zero exit status"
    exit $?
  end
end

module Homebrew
  def self.system cmd, *args
    puts "#{cmd} #{args*' '}" if ARGV.verbose?
    fork do
      yield if block_given?
      args.collect!{|arg| arg.to_s}
      exec(cmd.to_s, *args) rescue nil
      exit! 1 # never gets here unless exec failed
    end
    Process.wait
    $?.success?
  end
end

def with_system_path
  old_path = ENV['PATH']
  ENV['PATH'] = '/usr/bin:/bin'
  yield
ensure
  ENV['PATH'] = old_path
end

# Kernel.system but with exceptions
def safe_system cmd, *args
  unless Homebrew.system cmd, *args
    args = args.map{ |arg| arg.to_s.gsub " ", "\\ " } * " "
    raise ErrorDuringExecution, "Failure while executing: #{cmd} #{args}"
  end
end

# prints no output
def quiet_system cmd, *args
  Homebrew.system(cmd, *args) do
    # Redirect output streams to `/dev/null` instead of closing as some programs
    # will fail to execute if they can't write to an open stream.
    $stdout.reopen('/dev/null')
    $stderr.reopen('/dev/null')
  end
end

def curl *args
  curl = Pathname.new '/usr/bin/curl'
  raise "#{curl} is not executable" unless curl.exist? and curl.executable?

  flags = HOMEBREW_CURL_ARGS
  flags = flags.delete("#") if ARGV.verbose?

  args = [flags, HOMEBREW_USER_AGENT, *args]
  # See https://github.com/Homebrew/homebrew/issues/6103
  args << "--insecure" if MacOS.version < "10.6"
  args << "--verbose" if ENV['HOMEBREW_CURL_VERBOSE']
  args << "--silent" unless $stdout.tty?

  safe_system curl, *args
end

# Run scons using a Homebrew-installed version, instead of whatever
# is in the user's PATH
def scons *args
  scons = Formulary.factory("scons").opt_prefix/'bin/scons'
  raise "#{scons} is not executable" unless scons.exist? and scons.executable?
  safe_system scons, *args
end

def puts_columns items, star_items=[]
  return if items.empty?

  if star_items && star_items.any?
    items = items.map{|item| star_items.include?(item) ? "#{item}*" : item}
  end

  if $stdout.tty?
    # determine the best width to display for different console sizes
    console_width = `/bin/stty size`.chomp.split(" ").last.to_i
    console_width = 80 if console_width <= 0
    longest = items.sort_by { |item| item.length }.last
    optimal_col_width = (console_width.to_f / (longest.length + 2).to_f).floor
    cols = optimal_col_width > 1 ? optimal_col_width : 1

    IO.popen("/usr/bin/pr -#{cols} -t -w#{console_width}", "w"){|io| io.puts(items) }
  else
    puts items
  end
end

def which cmd, path=ENV['PATH']
  dir = path.split(File::PATH_SEPARATOR).find {|p| File.executable? File.join(p, cmd)}
  Pathname.new(File.join(dir, cmd)) unless dir.nil?
end

def which_editor
  editor = ENV.values_at('HOMEBREW_EDITOR', 'VISUAL', 'EDITOR').compact.first
  # If an editor wasn't set, try to pick a sane default
  return editor unless editor.nil?

  # Find Textmate
  return 'mate' if which "mate"
  # Find BBEdit / TextWrangler
  return 'edit' if which "edit"
  # Default to vim
  return '/usr/bin/vim'
end

def exec_editor *args
  return if args.to_s.empty?
  safe_exec(which_editor, *args)
end

def exec_browser *args
  browser = ENV['HOMEBREW_BROWSER'] || ENV['BROWSER'] || "open"
  safe_exec(browser, *args)
end

def safe_exec cmd, *args
  # This buys us proper argument quoting and evaluation
  # of environment variables in the cmd parameter.
  exec "/bin/sh", "-i", "-c", cmd + ' "$@"', "--", *args
end

# GZips the given paths, and returns the gzipped paths
def gzip *paths
  paths.collect do |path|
    with_system_path { safe_system 'gzip', path }
    Pathname.new("#{path}.gz")
  end
end

# Returns array of architectures that the given command or library is built for.
def archs_for_command cmd
  cmd = which(cmd) unless Pathname.new(cmd).absolute?
  Pathname.new(cmd).archs
end

def ignore_interrupts(opt = nil)
  std_trap = trap("INT") do
    puts "One sec, just cleaning up" unless opt == :quietly
  end
  yield
ensure
  trap("INT", std_trap)
end

def nostdout
  if ARGV.verbose?
    yield
  else
    begin
      require 'stringio'
      real_stdout = $stdout
      $stdout = StringIO.new
      yield
    ensure
      $stdout = real_stdout
    end
  end
end

def paths
  @paths ||= ENV['PATH'].split(File::PATH_SEPARATOR).collect do |p|
    begin
      File.expand_path(p).chomp('/')
    rescue ArgumentError
      onoe "The following PATH component is invalid: #{p}"
    end
  end.uniq.compact
end

module GitHub extend self
  ISSUES_URI = URI.parse("https://api.github.com/search/issues")

  Error = Class.new(RuntimeError)
  HTTPNotFoundError = Class.new(Error)

  class RateLimitExceededError < Error
    def initialize(reset, error)
      super <<-EOS.undent
        GitHub #{error}
        Try again in #{pretty_ratelimit_reset(reset)}, or create an API token:
          https://github.com/settings/applications
        and then set HOMEBREW_GITHUB_API_TOKEN.
        EOS
    end

    def pretty_ratelimit_reset(reset)
      if (seconds = Time.at(reset) - Time.now) > 180
        "%d minutes %d seconds" % [seconds / 60, seconds % 60]
      else
        "#{seconds} seconds"
      end
    end
  end

  class AuthenticationFailedError < Error
    def initialize(error)
      super <<-EOS.undent
        GitHub #{error}
        HOMEBREW_GITHUB_API_TOKEN may be invalid or expired, check:
          https://github.com/settings/applications
        EOS
    end
  end

  def open url, headers={}, &block
    # This is a no-op if the user is opting out of using the GitHub API.
    # Also disabled for older Ruby versions, which will either
    # not support HTTPS in open-uri or not have new enough certs.
    return if ENV['HOMEBREW_NO_GITHUB_API'] || RUBY_VERSION < '1.8.7'

    require 'net/https' # for exception classes below

    default_headers = {
      "User-Agent" => HOMEBREW_USER_AGENT,
      "Accept"     => "application/vnd.github.v3+json",
    }

    default_headers['Authorization'] = "token #{HOMEBREW_GITHUB_API_TOKEN}" if HOMEBREW_GITHUB_API_TOKEN
    Kernel.open(url, default_headers.merge(headers)) do |f|
      yield Utils::JSON.load(f.read)
    end
  rescue OpenURI::HTTPError => e
    handle_api_error(e)
  rescue SocketError, OpenSSL::SSL::SSLError => e
    raise Error, "Failed to connect to: #{url}\n#{e.message}", e.backtrace
  rescue Utils::JSON::Error => e
    raise Error, "Failed to parse JSON response\n#{e.message}", e.backtrace
  end

  def handle_api_error(e)
    if e.io.meta["x-ratelimit-remaining"].to_i <= 0
      reset = e.io.meta.fetch("x-ratelimit-reset").to_i
      error = Utils::JSON.load(e.io.read)["message"]
      raise RateLimitExceededError.new(reset, error)
    end

    case e.io.status.first
    when "401", "403"
      raise AuthenticationFailedError.new(e.message)
    when "404"
      raise HTTPNotFoundError, e.message, e.backtrace
    else
      raise Error, e.message, e.backtrace
    end
  end

  def issues_matching(query, qualifiers={})
    uri = ISSUES_URI.dup
    uri.query = build_query_string(query, qualifiers)
    open(uri) { |json| json["items"] }
  end

  def build_query_string(query, qualifiers)
    s = "q=#{uri_escape(query)}+"
    s << build_search_qualifier_string(qualifiers)
    s << "&per_page=100"
  end

  def build_search_qualifier_string(qualifiers)
    {
      :repo => "mistydemeo/tigerbrew",
      :in => "title",
    }.update(qualifiers).map { |qualifier, value|
      "#{qualifier}:#{value}"
    }.join("+")
  end

  def uri_escape(query)
    if URI.respond_to?(:encode_www_form_component)
      URI.encode_www_form_component(query)
    else
      require "erb"
      ERB::Util.url_encode(query)
    end
  end

  def issues_for_formula name
    issues_matching(name, :state => "open")
  end

  def print_pull_requests_matching(query)
    # Disabled on older Ruby versions - see above
    return if ENV['HOMEBREW_NO_GITHUB_API'] || RUBY_VERSION < '1.8.7'
    puts "Searching pull requests..."

    open_or_closed_prs = issues_matching(query, :type => "pr")

    open_prs = open_or_closed_prs.select {|i| i["state"] == "open" }
    if open_prs.any?
      puts "Open pull requests:"
      prs = open_prs
    elsif open_or_closed_prs.any?
      puts "Closed pull requests:"
      prs = open_or_closed_prs
    else
      return
    end

    prs.each { |i| puts "#{i["title"]} (#{i["html_url"]})" }
  end

  def private_repo?(user, repo)
    uri = URI.parse("https://api.github.com/repos/#{user}/#{repo}")
    open(uri) { |json| json["private"] }
  end
end
