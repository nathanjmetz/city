# Vehicles

Benchmark: real vehicles. Sizes come from spec sheets for the best seller in
each class; the fleet mix and colours follow US registration data, with
more pickups because this is the Midwest.

## Kinds

Household: sedan, hatchback, crossover, SUV, pickup (crew cab), work pickup
(regular cab, toolbox, ladder rack), minivan, sports car, motorcycle, van.
Most household kinds come in several body styles (compact and full-size
sedans, crew and mid-size pickups, wagon, EV crossover and more); a car's id
picks its style (`VehicleModels.variant()`), so it never changes.
Freight: delivery (step) van, 26 ft box truck, dump truck, concrete mixer,
tow truck, and semis with a 53 ft dry van, flatbed, grain hopper, tanker,
log trailer, end dump, USPS trailer or pot-belly livestock trailer.
Utility: bucket truck (Altec AT40G) for phone and power line crews.
Camping: Class C RV, Class A motorhome and a pickup with a slide-in camper,
used by out-of-town visitors (purpose "visitor").
Farm country: Amish black top buggy at a trot (about 10 mph); Daviess County,
next to Petersburg, has one of Indiana's largest Amish settlements. Buggies
turn up now and then on shopping trips.
Winter: while snow is on the ground, dump trucks and one contractor pickup in
three wear a plow blade (`VehicleModels.WINTER`).
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
