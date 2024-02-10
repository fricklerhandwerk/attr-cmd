{
  sources ? import ./npins,
  system ? builtins.currentSystem,
}:
(import ./. { inherit sources system; }).shell
