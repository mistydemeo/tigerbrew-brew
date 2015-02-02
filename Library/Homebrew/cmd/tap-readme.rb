module Homebrew
  def tap_readme
    name = ARGV.first
    raise "A name is required" if name.nil?

    titleized_name = name.dup
    titleized_name[0] = titleized_name[0].upcase

    template = <<-EOS.undent
    # Homebrew #{titleized_name}

    ## How do I install these formulae?
    `brew install homebrew/#{name}/<formula>`

    Or `brew tap homebrew/#{name}` and then `brew install <formula>`.

    Or install via URL (which will not receive updates):

    ```
    brew install https://raw.githubusercontent.com/Homebrew/homebrew-#{name}/master/<formula>.rb
    ```

    ## Documentation
    `brew help`, `man brew` or check [Tigerbrew's documentation](https://github.com/mistydemeo/tigerbrew/tree/master/share/doc/homebrew#readme).
    EOS

    puts template if ARGV.verbose?
    path = Pathname.new('./README.md')
    raise "#{path} already exists" if path.exist?
    path.write template
  end
end
