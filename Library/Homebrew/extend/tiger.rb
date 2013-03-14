# This file contains a set of monkeypatches to backport modern Ruby
# features into Tiger's ancient 1.8.2

class Object
	def instance_variable_defined?(ivar)
		if !ivar.to_s =~ /^@/
			raise NameError, "`#{ivar}' is not allowed as an instance variable name"
		end

		instance_variable_get(ivar) ? true : false
	end
end

module Enumerable
	def one?(&block)
		return map.size == 1 unless block
		select(&block).size == 1
	end
end

class Array
  def count(obj=nil)
    return length if obj.nil? unless block_given?

    if block_given?
      select {|o| yield(o)}.length
    else
      select {|o| o == obj}.length
    end
  end
end
