declare module "lucide-react" {
  import type { ReactElement, SVGProps } from "react";
  type IconProps = SVGProps<SVGSVGElement> & { size?: number | string; strokeWidth?: number };
  export const ArrowLeft: (props: IconProps) => ReactElement;
  export const ArrowRight: (props: IconProps) => ReactElement;
  export const Bell: (props: IconProps) => ReactElement;
  export const BookOpenCheck: (props: IconProps) => ReactElement;
  export const CalendarClock: (props: IconProps) => ReactElement;
  export const ChartNoAxesCombined: (props: IconProps) => ReactElement;
  export const Check: (props: IconProps) => ReactElement;
  export const ClipboardCheck: (props: IconProps) => ReactElement;
  export const ClipboardList: (props: IconProps) => ReactElement;
  export const Clock3: (props: IconProps) => ReactElement;
  export const Flag: (props: IconProps) => ReactElement;
  export const Play: (props: IconProps) => ReactElement;
  export const Search: (props: IconProps) => ReactElement;
  export const ShieldCheck: (props: IconProps) => ReactElement;
  export const UsersRound: (props: IconProps) => ReactElement;
}
