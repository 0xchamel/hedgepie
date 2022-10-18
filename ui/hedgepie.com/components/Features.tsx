import Image from "next/image";
import React from "react";
import { Box, Text } from "theme-ui";

interface FeaturesProps {
  type: "create" | "invest";
}

const content: any = {
  create: [
    {
      title: "Get access to proven investment strategies.",
      text: "HedgePie provides you with direct access to top DeFi strategies and investment pools designed and curated by experienced and expert DeFi investors.",
      action: "Learn more",
    },
    {
      title: "Join the best investors.",
      text: "HedgePie features investment strategies from expert investors who use and trust the platform. Spanning across two networks and dozens of DeFi protocols, including Polygon, UniSwap, PancakeSwap, Venus, BNB Chain, and many others.",
      action: "Learn more",
    },
    {
      title: "View the best performing strategies.",
      text: "Stop guessing what options to stake with. HedgePie knows how hard it can be to decide the best investment choice. That's why our leaderboard gives you a transparent list of historically high-performing investment funds. Choose from this leaderboard to minimize investment risks and maximize your profit.",
      action: "See Leaderboard",
    },
  ],
};

function Features(props: FeaturesProps) {
  const { type } = props;
  return (
    <Box
      sx={{
        backgroundColor: "#14114B",
        width: "100%",
        display: "flex",
        flexDirection: "row",
        gap: "30px",
        justifyContent: "center",
        alignItems: "center",
        padding: "100px",
      }}
    >
      <Box sx={{ position: "absolute", marginLeft: "-80px", zIndex: 0 }}>
        <Image
          src="/images/falling-coins-light.svg"
          width={3000}
          height={6000}
        />
      </Box>
      {content[type].map((e: any) => (
        <Box
          sx={{
            backgroundColor: "#FFFFFF",
            boxShadow: "0px 4px 20px rgba(0, 0, 0, 0.15)",
            borderRadius: "16px",
            display: "flex",
            flexDirection: "column",
            padding: "32px 24px",
            gap: "20px",
            fontFamily: "Open Sans",
            minWidth: "20rem",
            maxWidth: "25rem",
            height: "28rem",
            zIndex: 1,
          }}
        >
          <Text sx={{ color: "#14114B", fontSize: "24px", fontWeight: "700" }}>
            {e.title}
          </Text>
          <Text sx={{ color: "#1A1A1A", fontWeight: "300", fontSize: "18px" }}>
            {e.text}
          </Text>
          <Text
            sx={{ color: "#DF4886", fontSize: "16px", marginTop: "auto" }}
          >{`${e.action} →`}</Text>
        </Box>
      ))}
    </Box>
  );
}

export default Features;
