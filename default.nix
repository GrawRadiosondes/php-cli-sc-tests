{
  pkgs ? import <nixpkgs> {},
  imageTag ? "latest",
}: let
  system = pkgs.stdenv.hostPlatform.system;

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
        pcov
        pdo_mysql
        pdo_pgsql
        pgsql
        sockets
        zip
      ]);
    extraConfig = ''
      memory_limit = 1G
      pcov.enabled = 1
      pcov.directory = app
    '';
  };

  nginxConf = pkgs.runCommand "nginx-conf" {} ''
    mkdir -p $out/etc/nginx/conf.d
    cp -r ${./sounding-center/sail/nginx/conf.d}/* $out/etc/nginx/conf.d/
  '';

  debianBases = {
    "x86_64-linux" = {
      digest = "sha256:85dfcffff3c1e193877f143d05eaba8ae7f3f95cb0a32e0bc04a448077e1ac69";
      sha256 = "sha256-ftFPjbNU6RY80ax14YcfDKR/swoni7MLLgVYfXjV01w=";
    };
    "aarch64-linux" = {
      digest = "sha256:YOUR_ARM64_DEBIAN_DIGEST_HERE";
      sha256 = "sha256-YOUR_ARM64_NIX_HASH_HERE";
    };
  };

  debianBase = pkgs.dockerTools.pullImage {
    imageName = "debian";
    imageDigest = debianBases.${system}.digest;
    sha256 = debianBases.${system}.sha256;
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
    mkcert
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
    tag = "${imageTag}-${system}";
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
        "PATH=${pkgs.lib.makeBinPath ([phpWithExts] ++ myPackages)}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:./vendor/bin"
      ];
    };
  }
