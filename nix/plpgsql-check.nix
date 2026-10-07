{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:

stdenv.mkDerivation rec {
  pname = "plpgsql-check";
  version = "2.10.12";

  src = fetchFromGitHub {
    owner = "okbob";
    repo = "plpgsql_check";
    rev = "v${version}";
    hash = "sha256-99TemcnEgbhSY1YhSrIdAlclgIzak+X2PEaC/QUJwic=";
  };

  buildInputs = [ postgresql ];
  buildPhase = ''
    make
  '';
  installPhase = ''
    make prefix=$out/postgresql datadir=$out/postgresql libdir=$out/postgresql install
    mv $out/postgresql/* $out
    rmdir $out/postgresql
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
