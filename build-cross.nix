{ base }:

let pkgs = import ./pkgs.nix { useFetched = true; };
	lib = pkgs.lib;
	
	shellCopy = pkg: name: attr: sh: pkgs.runCommandLocal
		name
		({
			src = pkg.outPath;
			buildInputs = pkg.buildInputs;
		} // attr)
		''
			mkdir -p $out
			cp -rf $src/* $out/
			chmod -R +w $out
			${sh}
		'';

	wrapGApps = pkg: shellCopy pkg (pkg.name + "-nixos") {
		nativeBuildInputs = with pkgs; [
			wrapGAppsHook
		];
	} "";

	withPatchelf = patchelf: pkg: shellCopy pkg
		"${pkg.name}-${patchelf.name}" {}
		"${patchelf}/bin/${patchelf.name} $out/bin/*";

	output = name: packages: pkgs.runCommandLocal name {
		# Join the object of name to packages into a line-delimited list of strings.
		src = with lib; foldr
			(a: b: a + "\n" + b) ""
			(mapAttrsToList (name: pkg: "${name} ${pkg.outPath}") packages);
		buildInputs = with pkgs; [ coreutils ];
	} ''
		mkdir -p $out

		IFS=$'\n' readarray pkgs <<< "$src"

		for pkg in "''${pkgs[@]}"; {
			[[ "$pkg" == "" || "$pkg" == $'\n' ]] && continue

			read -r name path <<< "$pkg"
			tar -zcvf "$out/${base.pname}-$name.tar.gz" "$path/bin/${base.pname}"
		}
	'';

	basePkgs = {
		x86_64 = import ./cross-package.nix {
			inherit base;
			GOOS        = "linux";
			GOARCH      = "amd64";
			system      = "x86_64-linux";
			crossSystem = "x86_64-unknown-linux-gnu";
		};
		aarch64 = import ./cross-package.nix {
			inherit base;
			GOOS        = "linux";
			GOARCH      = "arm64";
			system      = "aarch64-linux";
			crossSystem = "aarch64-unknown-linux-gnu";
		};
	};

	outputs = with pkgs; {
		nixos-x86_64  = wrapGApps basePkgs.x86_64;
		linux-x86_64  = withPatchelf patchelf-x86_64 basePkgs.x86_64;
		nixos-aarch64 = wrapGApps basePkgs.aarch64;
		linux-aarch64 = withPatchelf patchelf-aarch64 basePkgs.aarch64;
	};

in output "${base.pname}-cross" outputs
