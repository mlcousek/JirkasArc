## ADDED Requirements

### Requirement: One line and one photo a day

Today SHALL show a card with the day's motivational line. The line SHALL be
chosen from 365 bundled lines by the local day of the year, so it is the
same all day and different the next day, in the app's language (Czech or
English).

#### Scenario: The same day shows the same line

- **WHEN** Today is opened twice on one calendar day
- **THEN** both show the same line

#### Scenario: A new day shows a new line

- **WHEN** the calendar day changes
- **THEN** the card shows a different line (and a different photo when two or more photos exist)

### Requirement: The photo is shown whole

The card SHALL show the day's photo in a frame of one fixed height, fitted
inside it without cropping any part, at its own aspect ratio.

#### Scenario: A tall photo

- **WHEN** the day's photo is taller than wide
- **THEN** all of it is visible, nothing is cut off, and the frame is the same height as for any other photo

#### Scenario: A wide photo

- **WHEN** the day's photo is wider than tall
- **THEN** all of it is visible and the rest of the frame is a blurred copy of it, not bare bars

### Requirement: Photos stay on the phone

The app SHALL read photos only from the phone's `Documents/Motivation`
folder, and SHALL offer "Add photos" that copies the owner's picks there. No
photo SHALL be part of the repository, a backup or any network request.

#### Scenario: No photos yet

- **WHEN** the folder is empty or missing
- **THEN** the card shows the line and an "Add photos" button, with no error

#### Scenario: A broken file

- **WHEN** one file in the folder cannot be decoded
- **THEN** it is skipped and the card shows the line (and another photo if there is one)

### Requirement: Off switch

Settings SHALL have a switch "Daily photo and quote", on by default. When off,
Today SHALL show no motivation card.
