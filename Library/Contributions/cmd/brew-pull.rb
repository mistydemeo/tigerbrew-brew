# Gets a patch from a GitHub commit or pull request and applies it to Homebrew.
# Optionally, installs it too.

require 'utils'
require 'formula'

def tap arg
  match = arg.match(%r[homebrew-(\w+)/])
  match[1].downcase if match
end

if ARGV.empty?
  onoe 'This command requires at least one argument containing a URL or pull request number'
end

if ARGV[0] == '--rebase'
  onoe 'You meant `git pull --rebase`.'
end

ARGV.named.each do|arg|
  if arg.to_i > 0
    url = 'https://github.com/mistydemeo/tigerbrew/pull/' + arg
  else
    url_match = arg.match HOMEBREW_PULL_OR_COMMIT_URL_REGEX
    unless url_match
      ohai 'Ignoring URL:', "Not a GitHub pull request or commit: #{arg}"
      next
    end

    url = url_match[0]
  end

  if tap_name = tap(url)
    user = url_match[1].downcase
    tap_dir = HOMEBREW_REPOSITORY/"Library/Taps/#{user}-#{tap_name}"
    safe_system "brew", "tap", "#{user}/#{tap_name}" unless tap_dir.exist?
    Dir.chdir tap_dir
  else
    Dir.chdir HOMEBREW_REPOSITORY
  end

  issue = arg.to_i > 0 ? arg.to_i : url_match[4]

  if ARGV.include? '--bottle'
    raise 'No pull request detected!' unless issue
    url = "https://github.com/BrewTestBot/homebrew/compare/homebrew:master...pr-#{issue}"
  end

  # GitHub provides commits'/pull-requests' raw patches using this URL.
  url += '.patch'

  # The cache directory seems like a good place to put patches.
  HOMEBREW_CACHE.mkpath
  patchpath = HOMEBREW_CACHE + File.basename(url)
  curl url, '-o', patchpath

  # Store current revision
  revision = `git rev-parse --short HEAD`.strip

  ohai 'Applying patch'
  patch_args = []
  patch_args << '--signoff' unless ARGV.include? '--clean'
  # Normally we don't want whitespace errors, but squashing them can break
  # patches so an option is provided to skip this step.
  if ARGV.include? '--ignore-whitespace' or ARGV.include? '--clean'
    patch_args << '--whitespace=nowarn'
  else
    patch_args << '--whitespace=fix'
  end
  patch_args << patchpath

  begin
    safe_system 'git', 'am', *patch_args
  rescue => e
    system 'git', 'am', '--abort'
    odie 'Patch failed to apply: aborted.'
  end

  if issue and not ARGV.include? '--clean'
    ohai "Patch closes issue ##{issue}"
    message = `git log HEAD^.. --format=%B`

    # If this is a pull request, append a close message.
    unless message.include? 'Closes #'
      issueline = "Closes ##{issue}."
      signed = 'Signed-off-by:'
      message = message.gsub signed, issueline + "\n\n" + signed
      safe_system 'git', 'commit', '--amend', '-q', '-m', message
    end
  end

  ohai 'Patch changed:'
  safe_system 'git', '--no-pager', 'diff', "#{revision}..", '--stat'

  if ARGV.include? '--install'
    `git diff #{revision}.. --name-status`.each_line do |line|
      status, filename = line.split
      # Don't try and do anything to removed files.
      if (status == 'A' or status == 'M') and filename.match /Formula\/.+\.rb$/ or tap url
        formula = File.basename(filename, '.rb')
        ohai "Installing #{formula}"
        install = Formula.factory(formula).installed? ? 'upgrade' : 'install'
        safe_system 'brew', install, '--debug', '--fresh', formula
      end
    end
  end
end
