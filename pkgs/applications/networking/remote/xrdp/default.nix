{ stdenv, fetchFromGitHub, fetchpatch, pkgconfig, which, perl, autoconf, automake, libtool, openssl, systemd, pam, fuse, libjpeg, libopus, nasm, xorg }:

let
  xorgxrdp = stdenv.mkDerivation rec {
    name = "xorgxrdp-${version}";
    version = "0.2.7";

    src = fetchFromGitHub {
      owner = "neutrinolabs";
      repo = "xorgxrdp";
      rev = "v${version}";
      sha256 = "15idwgcjgwa9in8y1bblpj67y7w0bfngc2sa0hd9hn0dinrlifrk";
    };

    nativeBuildInputs = [ pkgconfig autoconf automake which libtool nasm ];

    buildInputs = [ xorg.xorgserver ];

    postPatch = ''
      # patch from Debian, allows to run xrdp daemon under unprivileged user
      substituteInPlace module/rdpClientCon.c \
        --replace 'g_sck_listen(dev->listen_sck);' 'g_sck_listen(dev->listen_sck); g_chmod_hex(dev->uds_data, 0x0660);'

      substituteInPlace configure.ac \
        --replace 'moduledir=`pkg-config xorg-server --variable=moduledir`' "moduledir=$out/lib/xorg/modules" \
        --replace 'sysconfdir="/etc"' "sysconfdir=$out/etc"
    '';

    preConfigure = "./bootstrap";

    configureFlags = [ "XRDP_CFLAGS=-I${xrdp.src}/common"  ];

    enableParallelBuilding = true;
  };

  xrdp = stdenv.mkDerivation rec {
    version = "0.9.7";
    name = "xrdp-${version}";

    src = fetchFromGitHub {
      owner = "volth";
      repo = "xrdp";
      rev = "refs/heads/runtime-cfg-path-${version}";  # Fixes https://github.com/neutrinolabs/xrdp/issues/609; not a patch on top of the official repo because "xorgxrdp.configureFlags" above includes "xrdp.src" which must be patched already
      fetchSubmodules = true;
      sha256 = "1dw2zl9zh6win1q0kxj08n9fawpcrs1krjh5978wp0jmq8sdbn7k";
    };

    nativeBuildInputs = [ pkgconfig autoconf automake which libtool nasm ];

    buildInputs = [ openssl systemd pam fuse libjpeg libopus xorg.libX11 xorg.libXfixes xorg.libXrandr ];

    postPatch = ''
      substituteInPlace sesman/xauth.c --replace "xauth -q" "${xorg.xauth}/bin/xauth -q"
    '';

    preConfigure = ''
      (cd librfxcodec && ./bootstrap && ./configure --prefix=$out --enable-static --disable-shared)
      ./bootstrap
    '';
    dontDisableStatic = true;
    configureFlags = [ "--with-systemdsystemunitdir=/var/empty" "--enable-ipv6" "--enable-jpeg" "--enable-fuse" "--enable-rfxcodec" "--enable-opus" ];

    installFlags = [ "DESTDIR=$(out)" "prefix=" ];

    postInstall = ''
      # remove generated keys (as non-determenistic) and upstart script
      rm $out/etc/xrdp/{rsakeys.ini,key.pem,cert.pem,xrdp.sh}

      cp $src/keygen/openssl.conf $out/share/xrdp/openssl.conf

      substituteInPlace $out/etc/xrdp/sesman.ini --replace /etc/xrdp/pulse $out/etc/xrdp/pulse

      # remove all session types except Xorg (they are not supported by this setup)
      ${perl}/bin/perl -i -ne 'print unless /\[(X11rdp|Xvnc|console|vnc-any|sesman-any|rdp-any|neutrinordp-any)\]/ .. /^$/' $out/etc/xrdp/xrdp.ini

      # remove all session types and then add Xorg
      ${perl}/bin/perl -i -ne 'print unless /\[(X11rdp|Xvnc|Xorg)\]/ .. /^$/' $out/etc/xrdp/sesman.ini

      cat >> $out/etc/xrdp/sesman.ini <<EOF

      [Xorg]
      param=${xorg.xorgserver}/bin/Xorg
      param=-modulepath
      param=${xorgxrdp}/lib/xorg/modules,${xorg.xorgserver}/lib/xorg/modules
      param=-config
      param=${xorgxrdp}/etc/X11/xrdp/xorg.conf
      param=-noreset
      param=-nolisten
      param=tcp
      param=-logfile
      param=.xorgxrdp.%s.log
      EOF
    '';

    enableParallelBuilding = true;

    meta = with stdenv.lib; {
      description = "An open source RDP server";
      homepage = https://github.com/neutrinolabs/xrdp;
      license = licenses.asl20;
      maintainers = [ maintainers.volth ];
      platforms = platforms.linux;
    };
  };
in xrdp
