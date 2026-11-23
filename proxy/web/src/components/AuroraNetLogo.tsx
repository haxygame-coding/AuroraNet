import { cn } from "@/utils/helpers";
import auroranetFull from "@/assets/auroranet-full.svg";
import auroranetMark from "@/assets/auroranet.svg";

type Props = {
  size?: "small" | "default" | "large";
  mobile?: boolean;
};

const sizes = {
  small: {
    desktop: 14,
    mobile: 20,
  },
  default: {
    desktop: 22,
    mobile: 30,
  },
  large: {
    desktop: 24,
    mobile: 40,
  },
};

export const AuroraNetLogo = ({ size = "default", mobile = true }: Props) => {
  return (
    <>
      <img
        src={auroranetFull}
        height={sizes[size].desktop}
        style={{ height: sizes[size].desktop }}
        alt="AuroraNet Logo"
        className={cn(mobile && "hidden md:block", "group-hover:opacity-80 transition-all")}
      />
      {mobile && (
        <img
          src={auroranetMark}
          width={sizes[size].mobile}
          style={{ width: sizes[size].mobile }}
          alt="AuroraNet Logo"
          className={cn(mobile && "md:hidden ml-4")}
        />
      )}
    </>
  );
};
