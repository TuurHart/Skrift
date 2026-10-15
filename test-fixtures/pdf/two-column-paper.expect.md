# Tidal Drift in Low-Cost Harbour Sensors

Mira Okafor and Jonas Velde, Institute for Coastal Instruments

## Abstract

Cheap pressure sensors are now common in small harbours, but their readings wander over weeks. We logged eleven units beside a reference gauge for one winter and describe how the drift grows with water temperature, how much of it a weekly zero check removes, and what remains that only a second sensor can catch.

## 1 Introduction

A harbour master wants to know the water level at the quay, not the level at a tide station twenty kilometres away. Small pressure loggers make that possible for the price of a good pair of boots. The trouble starts after the first month, when a logger that agreed with the reference to a centimetre begins to read high on cold mornings and low after a warm spell.

Earlier work blamed the drift on fouling of the sensor port. Our loggers were cleaned every week, so fouling cannot explain what we saw. The pattern follows the water temperature instead, with a lag of about two days that matches the time the housing takes to settle.

## 2 Methods

Eleven loggers of three makes were tied to the same ladder as the reference gauge at the north quay. Each recorded pressure and temperature every ten minutes from November to March. A diver checked the ports each Monday and noted any growth, which stayed light all season.

We removed the air pressure using the harbour weather mast, then compared each logger with the reference over sliding windows of one week. A logger's drift is the slope of that difference against time, and its temperature response is the slope against the mean water temperature over the previous two days.

## 3 Results

Every logger drifted, the worst by nine centimetres over the winter and the best by under two. Nearly all of the drift tracked temperature: a cold week pushed the readings up and a mild week pulled them back. A weekly zero check against the reference removed most of the error, leaving a residual that rarely passed one centimetre.

One unit behaved differently. Its error rose steadily whatever the weather, and the zero check hid the trend until the diver found a cracked seal in February. Only the comparison with a second logger on the same ladder had shown it early.

## 4 Discussion

For a small harbour the lesson is simple. Correct for temperature, check the zero once a week, and hang two loggers rather than one. The second unit costs little and turns a slow silent failure into an obvious disagreement that anyone on the quay can see.

There is a cost to the second logger beyond its price. Someone has to read both records, notice when they part, and decide which one to trust. In our harbour that job fell to the volunteer who already checked the tide board each evening, and it added a few minutes to the round. Where nobody has those minutes, a simple alarm on the difference between the two units would do the same work, and we sketch one in the appendix.

The temperature correction itself is cheap to apply. Each logger already records the water temperature, so the correction needs no extra hardware, only a coefficient fitted over the first fortnight beside a reference. We found that coefficient stable across the winter for every unit of the same make, which means a harbour could fit it once for a batch rather than for every logger it buys.

## 5 Conclusion

Low-cost loggers can watch a small harbour well enough for daily use, provided their drift is treated as a known habit rather than a fault. Fit a temperature coefficient, zero the units weekly, and compare two of them, and the remaining error stays near one centimetre.

We did not test summer conditions, when warm water and heavy growth may change the picture, and we plan to repeat the study from June with the same ladder and the same divers.
