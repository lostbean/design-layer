{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "snips";
  version = "0.0.6-unstable-bd27573";

  src = fetchFromGitHub {
    owner = "cortesi";
    repo = "snips";
    rev = "bd27573539ed27f83ce359f1f7d566e830bd540a";
    sha256 = "0bwjxs24acf9ng92xn2qmjnra4brylg2n2vxhdf9hl5z1fm3p2vn";
  };
  cargoLock.lockFile = "${src}/Cargo.lock";

  meta = {
    description = "Keep Markdown snippets synchronized with tested source files";
    homepage = "https://github.com/cortesi/snips";
    license = lib.licenses.mit;
    mainProgram = "snips";
  };
}
