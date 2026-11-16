{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  autoconf,
  automake,
  pkg-config,
  libtool,
  which,
  perl,
  libxml2,
  geos,
  gdalMinimal,
  gmp,
  proj,
  protobufc
}:

stdenv.mkDerivation rec {
  pname = "postgis";
  version = "3.7.0";

  src = fetchFromGitHub {
    owner = "postgis";
    repo = "postgis";
    rev = "${version}";
    hash = "sha256-38bL4TdzciqOtwCH3Lbxuz9ZTb6qEmLBrDXujgJ/A5s=";
  };

  nativeBuildInputs = [ postgresql autoconf automake pkg-config libtool which perl libxml2 geos gdalMinimal gmp proj protobufc];
  buildInputs = [ postgresql autoconf automake pkg-config libtool which perl libxml2 geos gdalMinimal gmp proj protobufc];

  configurePhase = ''
    ./autogen.sh
    ./configure
  '';
  buildPhase = ''
    make
  '';
  installPhase = ''
    make install \
    	datadir=$out/share \
	pkglibdir=$out/lib \
	bindir=$out/bin \
	docdir=$out/share/doc \
	mandir=$out/share/man \
	PG_SHAREDIR=$out/share
  '';

  meta = with lib; {
    description = "";
    homepage = "";
    changelog = "";
    platforms = postgresql.meta.platforms;
    license = licenses.mit;
    maintainers = [ ];
  };
}

