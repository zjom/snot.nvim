{
  description = "snot.nvim: simple dated notes in Simple Note Format for Neovim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          # Neovim embeds LuaJIT (Lua 5.1), so the test tooling must target it too.
          lua = pkgs.luajit.withPackages (ps: [
            ps.busted
            ps.nlua
            ps.luarocks
          ]);
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.neovim
              pkgs.ripgrep
              lua
              pkgs.stylua
              pkgs.lua-language-server
            ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);
    };
}
