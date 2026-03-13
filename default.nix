{
  pkgs ? import <nixpkgs> {system = "x86_64-linux";},
  imageTag ? "latest",
}: let
  phpWithExts = pkgs.php85.buildEnv {
    extensions = {
      enabled,
      all,
    }:
      enabled
      ++ (with all; [
        bcmath
        gd
        intl
        mysqli
        pcntl
        pdo_mysql
        pdo_pgsql
        pgsql
        sockets
        zip
        xdebug
      ]);
    extraConfig = ''
      memory_limit = 1G
      xdebug.mode = coverage
    '';
  };

  nginxConf = pkgs.runCommand "nginx-conf" {} ''
    mkdir -p $out/etc/nginx/conf.d
    cp -r ${./sounding-center/sail/nginx/conf.d}/* $out/etc/nginx/conf.d/
  '';

  debianBase = pkgs.dockerTools.pullImage {
    imageName = "debian";
    imageDigest = "sha256:85dfcffff3c1e193877f143d05eaba8ae7f3f95cb0a32e0bc04a448077e1ac69";
    sha256 = "sha256-ftFPjbNU6RY80ax14YcfDKR/swoni7MLLgVYfXjV01w=";
  };

  myPackages = with pkgs; [
    bashInteractive
    bun
    cacert
    coreutils
    curl
    gcc
    git
    gnumake
    nginx
    nodePackages.node-gyp
    nodejs
    nss.tools
    openssh
    php85Packages.composer
    procps
    python3
  ];
in
  pkgs.dockerTools.buildLayeredImage {
    name = "docker.io/grawradiosondes/php-cli-sc-tests";
    tag = imageTag;
    maxLayers = 15;
    fromImage = debianBase;

    contents = [
      nginxConf
    ];

    fakeRootCommands = ''
      mkdir -p ./var/log/nginx ./var/cache/nginx ./var/run ./etc/nginx/certs
    '';

    config = {
      Cmd = ["/bin/bash"];
      Env = [
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        "CXXFLAGS=-std=c++20"
        "PATH=${pkgs.lib.makeBinPath ([phpWithExts] ++ myPackages)}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
      ];
    };
  }
