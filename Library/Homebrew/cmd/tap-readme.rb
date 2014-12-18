module Homebrew
  def tap_readme
    name = ARGV.first

    raise "A name is required" if name.nil?

    template = <<-EOS.undent
    Homebrew-#{name}
    =========#{'=' * name.size}

    How do I install these formulae?
    --------------------------------
    Just `brew tap homebrew/#{name}` and then `brew install <formula>`.

    If the formula conflicts with one from Homebrew/homebrew or another tap, you can `brew install homebrew/#{name}/<formula>`.

    You can also install via URL:

    ```
    brew install https://raw.githubusercontent.com/Homebrew/homebrew-#{name}/master/<formula>.rb
    ```

    Docs
    ----
    `brew help`, `man brew`, or the Homebrew [docs][].

    [docs]:https://github.com/Homebrew/homebrew/blob/master/share/doc/homebrew/README.md#readme
    EOS

    puts template if ARGV.verbose?
    path = Pathname.new('./README.md')
    raise "#{path} already exists" if path.exist?
    path.write template
  end
end
