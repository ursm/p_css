require 'bundler/gem_tasks'
require 'rake/testtask'

EXT_DIR    = File.expand_path('ext/css_native', __dir__)
TARGET_DIR = File.expand_path('target', __dir__)
LIB_DIR    = File.expand_path('lib/css',     __dir__)
EXT_NAME   = 'css_native'
EXT_SUFFIX = RbConfig::CONFIG.fetch('DLEXT')
EXT_OUTPUT = File.join(LIB_DIR, "#{EXT_NAME}.#{EXT_SUFFIX}")

desc 'Compile the Rust extension'
task :compile do
  Bundler.with_unbundled_env do
    sh(
      'cargo', 'build',
      '--release',
      '--manifest-path', File.join(EXT_DIR, 'Cargo.toml'),
      '--target-dir',    TARGET_DIR
    )
  end

  built = Dir[File.join(TARGET_DIR, 'release', "libcss_native.{so,dylib,dll}")].first or
    raise "cargo build produced no library under #{TARGET_DIR}/release"

  mkdir_p LIB_DIR
  cp built, EXT_OUTPUT
end

CLEAN_PATHS = [EXT_OUTPUT, TARGET_DIR]

desc 'Remove built extension artifacts'
task :clobber_ext do
  CLEAN_PATHS.each { rm_rf _1 }
end

task clobber: :clobber_ext

Rake::TestTask.new(:test) do |t|
  t.libs    << 'lib'
  t.libs    << 'test'
  t.pattern = 'test/**/test_*.rb'
  t.warning = false
end

# cibuildgem builds the binary on one runner and runs the test suite
# on another with the .so copied in — re-running `compile` there would
# re-build inside the wrong toolchain and overwrite the binary under
# test. Skip the prerequisite when CIBUILDGEM is set.
task test: :compile unless ENV['CIBUILDGEM']
task default: :test
