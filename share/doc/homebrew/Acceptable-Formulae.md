# Acceptable Formulae
Some formulae should not go in
[Homebrew/homebrew](https://github.com/Homebrew/homebrew). But there are
additional [Interesting Taps & Branches](Interesting-Taps-&-Branches.md) and anyone can start their
own!

### We try hard to avoid dupes in Homebrew/homebrew
Stuff that comes with OS X or is a library that is provided by
[RubyGems, CPAN or PyPi](http://github.com/Homebrew/homebrew/wiki/Gems,-Eggs-and-Perl-Modules)
should not be duplicated. There are good reasons for this:

* Duplicate libraries regularly break builds
* Subtle bugs emerge with duplicate libraries, and to a lesser extent,
duplicate tools
* We want our formulae to work with what comes with OS X

There are exceptions:

* Programs that a user will regularly interact with directly, like editors and
  language runtimes
* Libraries that provide functionality or contain security updates not found in
  the system version
* Things that are **designed to be installed in parallel to earlier versions of
  themselves**

#### Examples

  Formula         | Reason
  ---             | ---
  ruby, python    | People want newer versions
  bash            | OS X's bash is stuck at 3.2 because newer versions are licensed under GPLv3
  zsh             | This was a mistake, but it’s too late to remove it
  emacs, vim      | [Too popular to move to dupes](https://github.com/Homebrew/homebrew/pull/21594#issuecomment-21968819)
  subversion      | Originally added for 10.5, but people want the latest version
  libcurl         | Some formulae require a newer version than OS X provides
  openssl         | OS X's openssl is deprecated
  libxml2         | Historically, OS X's libxml2 has been buggy

We also maintain [a tap](https://github.com/Homebrew/homebrew-dueps) that
contains many duplicates not otherwise found in Homebrew.

### We don’t like tools that upgrade themselves
Software that can upgrade itself does not integrate well with Homebrew's own
upgrade functionality.

### We don’t like install-scripts that download things
Because that circumvents our hash-checks, makes finding/fixing bugs
harder, often breaks patches and disables the caching. Almost always you
can add a resource to the formula file to handle the
separate download and then the installer script will not attempt to load
that stuff on demand. Or there is a command line switch where you can
point it to the downloaded archive in order to avoid loading.

### We don’t like binary formulae
Our policy is that formulae in the core repository
([Homebrew/homebrew](https://github.com/Homebrew/homebrew)) must be built
from source. Binary-only formulae should go to
[Homebrew/homebrew-binary](https://github.com/Homebrew/homebrew-binary).

### Stable versions
Formulae in the core repository should have a stable version tagged by
the upstream project. Tarballs are preferred to git checkouts, and
tarballs should include the version in the filename whenever possible.

Software that does not provide a stable, tagged version, or had guidance to
always install the most recent version, should be put in
[Homebrew/homebrew-headonly](https://github.com/Homebrew/homebrew-headonly).

### Bindings
First check that there is not already a binding available via
[`gem`](http://rubygems.org/) or [`pip`](http://www.pip-installer.org/)
etc..

If not, then put bindings in the formula they bind to. This is more
useful to people. Just install the stuff! Having to faff around with
foo-ruby foo-perl etc. sucks.

### Niche (or self-submitted) Stuff<a name="Niche_Stuff"></a>
The software in question must be
* maintained
* known
* stable
* used
* have a homepage

We will reject formulae that seem too obscure, partly because they won’t
get maintained and partly because we have to draw the line somewhere.

We frown on authors submitting their own work unless it is very popular.

Don’t forget Homebrew is all git underneath! Maintain your own fork or
tap if you have to!

### Stuff that builds a .app
Don’t make your formula build an `.app` (native OS X Application), we
don’t want those things in Homebrew. Make it build a command line tool
or a library. However, we have a few exceptions to that, e.g. when the
App is just additional to CLI or if the GUI-application is non-native
for OS X and/or hard to get in binary elsewhere (example: font forge).
Check out the [homebrew-cask](https://github.com/phinze/homebrew-cask)
project if you’d like to brew native OS X Applications.

### Building under “superenv” is best
The “superenv” is code Homebrew uses to try to minimize finding
undeclared dependencies accidentally. Some formulae will only work under
the original “standard env” which is selected in a formula by adding
`env :std`. The preference for new formulae is that they be made to
work under superenv (which is the default) whenever possible.

### Sometimes there are exceptions
Even if all criteria are met we may not accept the formula.
Documentation tends to lag behind current decision-making. Although some
rejections may seem arbitrary or strange they are based from years of
experience making Homebrew work acceptably for our users.
