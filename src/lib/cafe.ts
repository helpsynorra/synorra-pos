type SocialLink = {
  id: "facebook" | "instagram" | "tiktok";
  label: string;
  href: string;
};

export const CAFE = {
  name: "synorra",
  tagline: "SYNORRA",
  hours: "10:30AM - 11:30PM",
  hoursNote: "DAILY",
  street: "Crispin Atilano St., Tetuan",
  landmark: "near RF Mariano & San Lorenzo entrance",
  city: "Zamboanga City, Philippines",
  phone: "+63 981 772 6937",
  phoneHref: "tel:+639817726937",
  email: "cadilmona@gmail.com",
  emailHref: "mailto:cadilmona@gmail.com",
  mapsHref:
    "https://www.google.com/maps/search/?api=1&query=Crispin+Atilano+St%2C+Tetuan%2C+Zamboanga+City",
  mapsEmbed:
    "https://maps.google.com/maps?q=Crispin%20Atilano%20St%2C%20Tetuan%2C%20Zamboanga%20City&output=embed",
  socials: [] as SocialLink[],
} as const;
