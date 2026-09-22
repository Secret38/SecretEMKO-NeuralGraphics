# FiveM GTAV Legacy build targets

SECRET EMKO currently declares these GTA V Legacy builds:

`1604, 2060, 2189, 2372, 2545, 2612, 2699, 2802, 2944, 3095, 3258, 3407, 3570, 3717, 3751, 3788, 3889`

For newer builds FiveM checks an exact Windows resource before loading an ASI. The generated resource syntax is:

```rc
FX_ASI_BUILD 3258 BEGIN "\0" END
```

The project intentionally keeps its graphics path independent of GTA executable offsets wherever possible. Declaring a build is a loader compatibility claim, not proof that every driver/runtime combination has been tested.
