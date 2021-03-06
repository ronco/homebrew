require 'formula'

class PerconaServer < Formula
  url 'http://www.percona.com/redir/downloads/Percona-Server-5.5/Percona-Server-5.5.15-21.0/source/Percona-Server-5.5.15-rel21.0.tar.gz'
  homepage 'http://www.percona.com'
  md5 'd04b6d1cc863f121f5d1eac8bc618331'
  version '5.5.15-21.0'

  keg_only "This brew conflicts with 'mysql'. It's safe to `brew link` if you haven't installed 'mysql'"

  depends_on 'cmake' => :build
  depends_on 'readline'
  depends_on 'pidof'

  fails_with_llvm "https://github.com/mxcl/homebrew/issues/issue/144"

  skip_clean :all # So "INSTALL PLUGIN" can work.

  def options
    [
      ['--with-tests', "Build with unit tests."],
      ['--with-embedded', "Build the embedded server."],
      ['--with-libedit', "Compile with EditLine wrapper instead of readline"],
      ['--universal', "Make mysql a universal binary"],
      ['--enable-local-infile', "Build with local infile loading support"]
    ]
  end

  # The CMAKE patches are so that on Lion we do not detect a private
  # pthread_init function as linkable. Patch sourced from the MySQL formula.
  def patches
    DATA
  end

  def install
    # Make sure the var/msql directory exists
    (var+"percona").mkpath

    args = std_cmake_parameters.split + [
      ".",
      "-DMYSQL_DATADIR=#{var}/percona",
      "-DINSTALL_MANDIR=#{man}",
      "-DINSTALL_DOCDIR=#{doc}",
      "-DINSTALL_INFODIR=#{info}",
      # CMake prepends prefix, so use share.basename
      "-DINSTALL_MYSQLSHAREDIR=#{share.basename}",
      "-DWITH_SSL=yes",
      "-DDEFAULT_CHARSET=utf8",
      "-DDEFAULT_COLLATION=utf8_general_ci",
      "-DSYSCONFDIR=#{etc}"
    ]

    # To enable unit testing at build, we need to download the unit testing suite
    if ARGV.include? '--with-tests'
      args << "-DENABLE_DOWNLOADS=ON"
    else
      args << "-DWITH_UNIT_TESTS=OFF"
    end

    # Build the embedded server
    args << "-DWITH_EMBEDDED_SERVER=ON" if ARGV.include? '--with-embedded'

    # Compile with readline unless libedit is explicitly chosen
    args << "-DWITH_READLINE=yes" unless ARGV.include? '--with-libedit'

    # Make universal for binding to universal applications
    args << "-DCMAKE_OSX_ARCHITECTURES='i386;x86_64'" if ARGV.build_universal?

    # Build with local infile loading support
    args << "-DENABLED_LOCAL_INFILE=1" if ARGV.include? '--enable-local-infile'

    system "cmake", *args
    system "make"
    system "make install"

    (prefix+'com.percona.mysqld.plist').write startup_plist

    # Don't create databases inside of the prefix!
    # See: https://github.com/mxcl/homebrew/issues/4975
    rm_rf prefix+'data'

    # Link the setup script into bin
    ln_s prefix+'scripts/mysql_install_db', bin+'mysql_install_db'
    # Fix up the control script and link into bin
    inreplace "#{prefix}/support-files/mysql.server" do |s|
      s.gsub!(/^(PATH=".*)(")/, "\\1:#{HOMEBREW_PREFIX}/bin\\2")
    end
    ln_s "#{prefix}/support-files/mysql.server", bin
  end

  def caveats; <<-EOS.undent
    Set up databases to run AS YOUR USER ACCOUNT with:
        unset TMPDIR
        mysql_install_db --verbose --user=`whoami` --basedir="$(brew --prefix percona-server)" --datadir=#{var}/percona --tmpdir=/tmp

    To set up base tables in another folder, or use a different user to run
    mysqld, view the help for mysqld_install_db:
        mysql_install_db --help

    and view the MySQL documentation:
      * http://dev.mysql.com/doc/refman/5.5/en/mysql-install-db.html
      * http://dev.mysql.com/doc/refman/5.5/en/default-privileges.html

    To run as, for instance, user "mysql", you may need to `sudo`:
        sudo mysql_install_db ...options...

    Start mysqld manually with:
        mysql.server start

        Note: if this fails, you probably forgot to run the first two steps up above

    A "/etc/my.cnf" from another install may interfere with a Homebrew-built
    server starting up correctly.

    To connect:
        mysql -uroot

    To launch on startup:
    * if this is your first install:
        mkdir -p ~/Library/LaunchAgents
        cp #{prefix}/com.percona.mysqld.plist ~/Library/LaunchAgents/
        launchctl load -w ~/Library/LaunchAgents/com.percona.mysqld.plist

    * if this is an upgrade and you already have the com.percona.mysqld.plist loaded:
        launchctl unload -w ~/Library/LaunchAgents/com.percona.mysqld.plist
        cp #{prefix}/com.percona.mysqld.plist ~/Library/LaunchAgents/
        launchctl load -w ~/Library/LaunchAgents/com.percona.mysqld.plist

    You may also need to edit the plist to use the correct "UserName".

    EOS
  end

  def startup_plist; <<-EOPLIST.undent
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>KeepAlive</key>
      <true/>
      <key>Label</key>
      <string>com.percona.mysqld</string>
      <key>Program</key>
      <string>#{bin}/mysqld_safe</string>
      <key>RunAtLoad</key>
      <true/>
      <key>UserName</key>
      <string>#{`whoami`.chomp}</string>
      <key>WorkingDirectory</key>
      <string>#{var}</string>
    </dict>
    </plist>
    EOPLIST
  end
end


__END__
--- old/scripts/mysqld_safe.sh  2009-09-02 04:10:39.000000000 -0400
+++ new/scripts/mysqld_safe.sh  2009-09-02 04:52:55.000000000 -0400
@@ -383,7 +383,7 @@
 fi

 USER_OPTION=""
-if test -w / -o "$USER" = "root"
+if test -w /sbin -o "$USER" = "root"
 then
   if test "$user" != "root" -o $SET_USER = 1
   then
diff --git a/scripts/mysql_config.sh b/scripts/mysql_config.sh
index efc8254..8964b70 100644
--- a/scripts/mysql_config.sh
+++ b/scripts/mysql_config.sh
@@ -132,7 +132,8 @@ for remove in DDBUG_OFF DSAFEMALLOC USAFEMALLOC DSAFE_MUTEX \
               DEXTRA_DEBUG DHAVE_purify O 'O[0-9]' 'xO[0-9]' 'W[-A-Za-z]*' \
               'mtune=[-A-Za-z0-9]*' 'mcpu=[-A-Za-z0-9]*' 'march=[-A-Za-z0-9]*' \
               Xa xstrconst "xc99=none" AC99 \
-              unroll2 ip mp restrict
+              unroll2 ip mp restrict \
+              mmmx 'msse[0-9.]*' 'mfpmath=sse' w pipe 'fomit-frame-pointer' 'mmacosx-version-min=10.[0-9]'
 do
   # The first option we might strip will always have a space before it because
   # we set -I$pkgincludedir as the first option
diff --git a/configure.cmake b/configure.cmake
index 0014c1d..21fe471 100644
--- a/configure.cmake
+++ b/configure.cmake
@@ -391,7 +391,11 @@ CHECK_FUNCTION_EXISTS (pthread_attr_setscope HAVE_PTHREAD_ATTR_SETSCOPE)
 CHECK_FUNCTION_EXISTS (pthread_attr_setstacksize HAVE_PTHREAD_ATTR_SETSTACKSIZE)
 CHECK_FUNCTION_EXISTS (pthread_condattr_create HAVE_PTHREAD_CONDATTR_CREATE)
 CHECK_FUNCTION_EXISTS (pthread_condattr_setclock HAVE_PTHREAD_CONDATTR_SETCLOCK)
-CHECK_FUNCTION_EXISTS (pthread_init HAVE_PTHREAD_INIT)
+
+IF (NOT CMAKE_OSX_SYSROOT)
+    CHECK_FUNCTION_EXISTS (pthread_init HAVE_PTHREAD_INIT)
+ENDIF (NOT CMAKE_OSX_SYSROOT)
+
 CHECK_FUNCTION_EXISTS (pthread_key_delete HAVE_PTHREAD_KEY_DELETE)
 CHECK_FUNCTION_EXISTS (pthread_rwlock_rdlock HAVE_PTHREAD_RWLOCK_RDLOCK)
 CHECK_FUNCTION_EXISTS (pthread_sigmask HAVE_PTHREAD_SIGMASK)
