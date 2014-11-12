# Interesting Taps & Branches
A Tap is homebrew-speak for a git repository containing extra formulae.
Homebrew has the capability to add (and remove) multiple taps to your local installation with the `brew tap` and `brew untap` command. Type `man brew` in your Terminal. The main repository https://github.com/Homebrew/homebrew often called "Homebrew/homebrew" is always built-in.

## Main Taps

*   [homebrew/science](https://github.com/Homebrew/homebrew-science)
    - A collection of scientific libraries and tools.

*   [homebrew/dupes](https://github.com/Homebrew/homebrew-dupes)
    - Need GDB or a newer Tk? System duplicates go here.

*   [homebrew/versions](https://github.com/Homebrew/homebrew-versions)
    - Need e.g. older or newer versions of Python? Newer versions of GCC?

*   [homebrew/games](https://github.com/Homebrew/homebrew-games)
    - Game formulae.

*   [homebrew/apache](https://github.com/Homebrew/homebrew-apache)
    - A tap for Apache modules, extending OS X's built-in Apache. These brews may require unconventional additional setup, as explained in the caveats.

*   [homebrew/headonly](https://github.com/Homebrew/homebrew-headonly)
    - A tap for brews that don't have stable versions.

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
    - Feature rich Nginx tap for modules

*   [homebrew/binary](https://github.com/Homebrew/homebrew-binary)
    - Precompiled binary formulae.


`brew search` looks in these main taps and as well in [Homebrew/homebrew](https://github.com/Homebrew/homebrew). So don't worry about missing stuff. We will add other taps to the search as they become well maintained and popular.

You can be added as a maintainer for one of the Homebrew organization taps and aid the project! If you are interested write to our list: homebrew@librelist.com. We want your help!


## Other Interesting Taps

*   [larsimmisch/avr](https://github.com/larsimmisch/homebrew-avr)
    - GNU AVR toolchain (avr-gcc etc. for Arduino hackers).

*   [titanous/gnuradio](https://github.com/titanous/homebrew-gnuradio)
    -  GNU Radio and friends running on OS X.

*   [besport/ocaml](https://github.com/besport/homebrew-ocaml)
    - A tap for Ocaml libraries, though with caveats, it requires you install its customized ocaml formula. Perhaps a template for more work.

*   [nolith/embedded](https://github.com/nolith/homebrew-embedded)
    - Flashing tools for embedded devices and olsrd for mesh network routing.

*   [anarchivist/forensics](https://github.com/anarchivist/homebrew-forensics)
    - Digital forensics-related formulae; mostly head-only, binary-only, or unstable.

*   [petere/postgresql](https://github.com/petere/homebrew-postgresql)
    - Allows installing multiple PostgreSQL versions in parallel.

*   [iMichka/MacVTKITKPythonBottles](https://github.com/iMichka/homebrew-MacVTKITKPythonBottles)
    - VTK and ITK binaries with Python wrapping.

*   [edavis/emacs](https://github.com/edavis/homebrew-emacs)
    - A tap for Emacs packages.

## Interesting Branches (aka forks)

*   [mistydemeo/tigerbrew](https://github.com/mistydemeo/tigerbrew)
    - Experimental Tiger PowerPC version

*   [codebutler](https://github.com/codebutler/homebrew/commits/master)
    - Preliminary support for GTK+ using the Quartz (native OS X) back-end

*   [paxan/linux](https://github.com/paxan/homebrew/commits/linux)
    - Experimental Linux version

*   [homebrew/linuxbrew](https://github.com/Homebrew/linuxbrew)
    - Experimental Linux version

*   [rmyers/homebrew](https://github.com/rmyers/homebrew)
    - Experimental Solaris version

*   [nddrylliog/winbrew](https://github.com/nddrylliog/winbrew)
    - Experimental Windows version

*   [wilmoore/homebrew-home](https://github.com/wilmoore/homebrew-home)
    - Homebrew install for those that like to Homebrew @ $HOME (i.e. ~/.homebrew).


## Technical Details

Your taps are git repositories located at `$(brew --prefix)/Library/Taps`.
