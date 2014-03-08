require 'formula'

# `brew uses foo bar` returns formulae that use both foo and bar
# If you want the union, run the command twice and concatenate the results.
# The intersection is harder to achieve with shell tools.

module Homebrew extend self
  def uses
    raise FormulaUnspecifiedError if ARGV.named.empty?

    used_formulae = ARGV.formulae
    formulae = (ARGV.include? "--installed") ? Formula.installed : Formula

    uses = []
    formulae.each do |f|
      used_formulae.all? do |ff|
        if ARGV.flag? '--recursive'
          if f.recursive_dependencies.any? { |dep| dep.name == ff.name }
            uses << f.to_s
          elsif f.recursive_requirements.any? { |req| req.name == ff.name }
            uses << f.to_s
          end
        else
          if f.deps.any? { |dep| dep.name == ff.name }
            uses << f.to_s
          elsif f.requirements.any? { |req| req.name == ff.name }
            uses << f.to_s
          end
        end
      end
    end

    puts_columns uses
  end
end
