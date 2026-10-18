declare module "nodemailer" {
  type GmailTransportOptions = {
    service: "gmail";
    auth: { user: string; pass: string };
  };

  type RecoveryMessage = {
    from: { name: string; address: string };
    to: string;
    subject: string;
    text: string;
    html: string;
  };

  const nodemailer: {
    createTransport(options: GmailTransportOptions): {
      sendMail(message: RecoveryMessage): Promise<unknown>;
    };
  };

  export default nodemailer;
}
