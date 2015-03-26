{ stdenv, fetchurl
, bzip2, curl, expat, jsoncpp, libarchive, xz, zlib
, useNcurses ? false, ncurses, useQt4 ? false, qt4
}:

with stdenv.lib;

let
  os = stdenv.lib.optionalString;
  majorVersion = "3.2";
  minorVersion = "1";
  version = "${majorVersion}.${minorVersion}";
in

stdenv.mkDerivation rec {
  name = "cmake-${os useNcurses "cursesUI-"}${os useQt4 "qt4UI-"}${version}";

  inherit majorVersion;

  src = fetchurl {
    url = "${meta.homepage}files/v${majorVersion}/cmake-${version}.tar.gz";
    sha256 = "0b2hy4p0aa9zshlxyw9nmlh5q8q1lmnwmb594rvh6sx2n7v1r7vm";
  };

  enableParallelBuilding = true;

  patches =
    # Don't search in non-Nix locations such as /usr, but do search in
    # Nixpkgs' Glibc.
    optional (stdenv ? glibc) ./search-path-3.2.patch ++
    optional (stdenv ? cross) (fetchurl {
      name = "fix-darwin-cross-compile.patch";
      url = "http://public.kitware.com/Bug/file_download.php?"
          + "file_id=4981&type=bug";
      sha256 = "16acmdr27adma7gs9rs0dxdiqppm15vl3vv3agy7y8s94wyh4ybv";
    }) ++
    # fix cmake detection of openssl libs
    # see: http://public.kitware.com/Bug/bug_relationship_graph.php?bug_id=15386
    #      and http://www.cmake.org/gitweb?p=cmake.git;a=commitdiff;h=c5d9a8283cfac15b4a5a07f18d5eb10c1f388505#patch1
    [./cmake_find_openssl_for_openssl-1.0.1m_and_up.patch];

  buildInputs =
    [ bzip2 curl expat libarchive xz zlib ]
    ++ optional (jsoncpp != null) jsoncpp
    ++ optional useNcurses ncurses
    ++ optional useQt4 qt4;

  CMAKE_PREFIX_PATH = stdenv.lib.concatStringsSep ":" buildInputs;

  configureFlags =
    [
      "--docdir=/share/doc/${name}"
      "--mandir=/share/man"
      "--system-libs"
    ]
    ++ optional (jsoncpp == null) "--no-system-jsoncpp"
    ++ optional useQt4 "--qt-gui";

  setupHook = ./setup-hook.sh;

  dontUseCmakeConfigure = true;

  preConfigure = optionalString (stdenv ? glibc)
    ''
      source $setupHook
      fixCmakeFiles .
      substituteInPlace Modules/Platform/UnixPaths.cmake \
        --subst-var-by glibc ${stdenv.glibc}
    '';

  meta = {
    homepage = http://www.cmake.org/;
    description = "Cross-Platform Makefile Generator";
    platforms = if useQt4 then qt4.meta.platforms else stdenv.lib.platforms.all;
    maintainers = with stdenv.lib.maintainers; [ urkud mornfall ttuegel ];
  };
}
