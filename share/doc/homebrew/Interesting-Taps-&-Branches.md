# Interesting Taps & Branches
A Tap is homebrew-speak for a git repository containing extra formulae.
Tigerbrew has the capability to add (and remove) multiple taps to your local installation with the `brew tap` and `brew untap` command. Type `man brew` in your Terminal. The main repository https://github.com/mistydemeo/tigerbrew often called "mistydemeo/tigerbrew" is always built-in.

## Main Taps

*   [homebrew/science](https://github.com/Homebrew/homebrew-science)
    - A collection of scientific libraries and tools.

*   [homebrew/dupes](https://github.com/Homebrew/homebrew-dupes)
    - Need GDB or a newer Tk? System duplicates go here.

*   [homebrew/versions](https://github.com/Homebrew/homebrew-versions)
    - Need e.g. older or newer versions of Postgresql? Older versions of GCC?

*   [homebrew/games](https://github.com/Homebrew/homebrew-games)
    - Game or gaming-emulation related formulae.

*   [homebrew/apache](https://github.com/Homebrew/homebrew-apache)
    - A tap for Apache modules, extending OS X's built-in Apache. These brews may require unconventional additional setup, as explained in the caveats.

*   [homebrew/head-only](https://github.com/Homebrew/homebrew-head-only)
    - A tap for brews that only have unstable, unreleased versions.

*   [homebrew/devel-only](https://github.com/Homebrew/homebrew-devel-only)
    - A tap for brews that only have pre-release/development versions.

*   [homebrew/php](https://github.com/Homebrew/homebrew-php)
    - Repository for php-related formulae.

*   [homebrew/python](https://github.com/Homebrew/homebrew-python)
    - A few Python formulae that do not build well with `pip` alone.

*   [homebrew/completions](https://github.com/Homebrew/homebrew-completions)
    - Shell completion formulae.

*   [homebrew/x11](https://github.com/Homebrew/homebrew-x11)
    - Formulae with hard X11 dependencies.

*   [homebrew/boneyard](https://github.com/Homebrew/homebrew-boneyard)
    - Formula are not deleted, they are moved here.

*   [homebrew/nginx](https://github.com/Homebrew/homebrew-nginx)
    - Feature rich Nginx tap for modules.

*   [homebrew/binary](https://github.com/Homebrew/homebrew-binary)
    - Precompiled binary formulae.

*   [homebrew/brewdler](https://github.com/Homebrew/homebrew-brewdler)
    - A Bundler-equivalent for installing project dependencies from Homebrew.


`brew search` looks in these main taps and as well in [mistydemeo/tigerbrew](https://github.com/mistydemeo/tigerbrew). So don't worry about missing stuff. We will add other taps to the search as they become well maintained and popular.

You can be added as a maintainer for one of the Homebrew organization taps and aid the project! If you are interested write to our list: homebrew@librelist.com. We want your help!


## Other Interesting Taps

*   [larsimmisch/avr](https://github.com/larsimmisch/homebrew-avr)
    - GNU AVR toolchain (avr-gcc etc. for Arduino hackers).

*   [titanous/gnuradio](https://github.com/titanous/homebrew-gnuradio)
    -  GNU Radio and friends running on OS X.

*   [besport/ocaml](https://github.com/besport/homebrew-ocaml)
    - A tap for Ocaml libraries, though with caveats, it requires you install its customized ocaml formula. Perhaps a template for more work.

*   [petere/postgresql](https://github.com/petere/homebrew-postgresql)
    - Allows installing multiple PostgreSQL versions in parallel.

*   [iMichka/MacVTKITKPythonBottles](https://github.com/iMichka/homebrew-MacVTKITKPythonBottles)
    - VTK and ITK binaries with Python wrapping.

*   [edavis/emacs](https://github.com/edavis/homebrew-emacs)
    - A tap for Emacs packages.

## Interesting Branches (aka forks)

*   [mistydemeo/tigerbrew](https://github.com/mistydemeo/tigerbrew)
    - Experimental Tiger PowerPC version

*   [homebrew/linuxbrew](https://github.com/Homebrew/linuxbrew)
    - Experimental Linux version

*   [wilmoore/homebrew-home](https://github.com/wilmoore/homebrew-home)
    - Tigerbrew install for those that like to Tigerbrew @ $HOME (i.e. ~/.homebrew).

*   [nddrylliog/homebrew-mingw](https://github.com/nddrylliog/homebrew-mingw)
    - An experimental port of Tigerbrew for Windows (with an MSYS/MinGW environment).


## Technical Details

Your taps are git repositories located at `$(brew --prefix)/Library/Taps`.
