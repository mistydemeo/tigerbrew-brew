require "tmpdir"
require "pathname"

HOMEBREW_TEMP = Pathname.new(ENV["HOMEBREW_TEMP"] || Dir.tmpdir)

TEST_TMPDIR = ENV.fetch("HOMEBREW_TEST_TMPDIR") { |k|
  dir = Dir.mktmpdir("homebrew_tests", HOMEBREW_TEMP)
  at_exit { FileUtils.remove_entry(dir) }
  ENV[k] = dir
}

HOMEBREW_PREFIX        = Pathname.new(TEST_TMPDIR).join("prefix")
HOMEBREW_REPOSITORY    = HOMEBREW_PREFIX
HOMEBREW_LIBRARY       = HOMEBREW_REPOSITORY+"Library"
HOMEBREW_LIBRARY_PATH  = Pathname.new(File.expand_path("../../..", __FILE__))
HOMEBREW_LOAD_PATH     = [File.expand_path("..", __FILE__), HOMEBREW_LIBRARY_PATH].join(":")
HOMEBREW_CACHE         = HOMEBREW_PREFIX.parent+"cache"
HOMEBREW_CACHE_FORMULA = HOMEBREW_PREFIX.parent+"formula_cache"
HOMEBREW_CELLAR        = HOMEBREW_PREFIX.parent+"cellar"
HOMEBREW_LOGS          = HOMEBREW_PREFIX.parent+"logs"

TESTBALL_SHA1 = "be478fd8a80fe7f29196d6400326ac91dad68c37"
TESTBALL_SHA256 = "91e3f7930c98d7ccfb288e115ed52d06b0e5bc16fec7dce8bdda86530027067b"
TESTBALL_PATCHES_SHA256 = "799c2d551ac5c3a5759bea7796631a7906a6a24435b52261a317133a0bfb34d9"
PATCH_A_SHA256 = "83404f4936d3257e65f176c4ffb5a5b8d6edd644a21c8d8dcc73e22a6d28fcfa"
PATCH_B_SHA256 = "57958271bb802a59452d0816e0670d16c8b70bdf6530bcf6f78726489ad89b90"
