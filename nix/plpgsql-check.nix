{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "plpgsql-check";
  version = "2.10.16";

  src = fetchFromGitHub {
    owner = "okbob";
    repo = "plpgsql_check";
    rev = "v${version}";
    hash = "sha256-L+mb3nrO10kN9mlItuSg4SiUdP+zWhXEk74vWRY+QsQ=";
  };

  buildInputs = [ postgresql ];

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
    description = "Linter tool for language PL/pgSQL";
    homepage = "https://github.com/okbob/plpgsql_check";
    changelog = "https://github.com/okbob/plpgsql_check/releases/tag/v${version}";
    platforms = postgresql.meta.platforms;
    license = licenses.mit;
    maintainers = [ maintainers.marsam ];
  };
}
