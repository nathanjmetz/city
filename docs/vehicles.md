# Vehicles

Benchmark: real vehicles. Sizes come from spec sheets for the best seller in
each class; the fleet mix and colours follow US registration data, with
more pickups because this is the Midwest.

## Kinds

Household: sedan, hatchback, crossover, SUV, pickup (crew cab), work pickup
(regular cab, toolbox, ladder rack), minivan, sports car, motorcycle, van.
Freight: delivery (step) van, 26 ft box truck, dump truck, tow truck, and
semis with a 53 ft dry van, flatbed, grain hopper or tanker.
Services: school bus, city bus, garbage truck, fire engine, police
interceptor, ambulance. Farm: row-crop tractor, combine.

## Purpose

Every vehicle has a job, like in Cities: Skylines. The simulation names the
job and `VehicleTypes.for_purpose()` gives the right vehicle (grain goes in
hopper semis, factory goods in box trucks and semis, fire calls get a fire
engine). `pick()` is the fallback for background trips.

## Code

- `scripts/vehicles/vehicle_types.gd`: sizes, driving specs (`spec()`), fleet
  mix (`pick()`, `for_purpose()`), and colours (`paint()`).
- `scripts/vehicles/vehicle_models.gd`: builds every model from code, at two
  levels of detail. Origin at the front bumper.
- `scripts/vehicles/vehicle_material.gd`: one shader for all of them: paint,
  glass, chrome, lights that brighten when braking, flashing beacons.
- `scripts/traffic/traffic_view.gd`: one batch per model and detail level.
  Bodies point from the front bumper to the rear axle, so long vehicles
  swing wide in turns; semi trailers hinge at the fifth wheel.
- `tools/vehicle_shot.gd`: lines up every model for photo checks.
