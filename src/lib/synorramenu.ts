import { DEFAULT_MENU } from "@/lib/menu";
import type { MenuItem } from "@/lib/types";

// Halimbawa: Kunin lang ang mga signature drinks o specific categories mula sa DEFAULT_MENU
// o kaya ay i-filter base sa gusto mong logic na galing din sa menu.ts
export const SYNORRA_MENU: MenuItem[] = DEFAULT_MENU.filter(
  (item) => 
    item.category === "Signature Coffee" || 
    item.category === "Non-Coffee / Matcha" ||
    item.category === "Classic Coffee"
);