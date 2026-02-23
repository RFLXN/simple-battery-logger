{ lib
, stdenvNoCC
, makeWrapper
, coreutils
, jq
, util-linux
}:

stdenvNoCC.mkDerivation {
  pname = "battery-logger";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    install -Dm755 scripts/battery-logger.sh $out/libexec/battery-logger
    patchShebangs $out/libexec/battery-logger

    makeWrapper $out/libexec/battery-logger $out/bin/battery-logger \
      --prefix PATH : ${lib.makeBinPath [ coreutils jq util-linux ]}

    mkdir -p $out/lib/systemd/system
    substituteAll systemd/battery-logger.service.in $out/lib/systemd/system/battery-logger.service
    install -Dm644 systemd/battery-logger.timer $out/lib/systemd/system/battery-logger.timer

    runHook postInstall
  '';

  meta = with lib; {
    description = "Simple battery percentage logger with systemd timer";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "battery-logger";
  };
}
