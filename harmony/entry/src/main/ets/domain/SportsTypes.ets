export class SportsVenue {
  id: string = '';
  name: string = '';
  type: string = '';
  capacity: number = 0;
}

export class SportsReservation {
  id: string = '';
  venueId: string = '';
  venueName: string = '';
  date: string = '';
  timeSlot: string = '';
  status: string = '';
}
