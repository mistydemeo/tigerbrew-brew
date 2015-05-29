# Extracted from the backports gem, by Marc-Andre Lafortune
# https://github.com/marcandre/backports
# 
# Copyright (c) 2009 Marc-Andre Lafortune
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

unless Enumerable.method_defined? :max_by
  require 'vendor/backports/extreme_object'
  require 'enumerator'

  module Enumerable
    def max_by
      return to_enum(:max_by) unless block_given?
      max_object, max_result = nil, Backports::MOST_EXTREME_OBJECT_EVER
      each do |object|
        result = yield object
        max_object, max_result = object, result if max_result < result
      end
      max_object
    end
  end
end
