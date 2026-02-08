package main

import (
	"context"
	"log"
	"os"

	"github.com/maileroo/maileroo-go-sdk/maileroo"
)

func main() {
	sendEmail()
}

func sendEmail() {
	subject, htmlContent := parseArguments()

	apiKey := os.Getenv("MAILEROO_API_KEY")
	if apiKey == "" {
		log.Fatal("MAILEROO_API_KEY environment variable is not set")
	}

	emailTo := os.Getenv("EMAIL_TO")
	if emailTo == "" {
		log.Fatal("EMAIL_TO environment variable is not set")
	}

	emailFrom := os.Getenv("EMAIL_FROM")
	if emailFrom == "" {
		log.Fatal("EMAIL_FROM environment variable is not set")
	}

	client, err := maileroo.NewClient(apiKey, 10)

	if err != nil {
		log.Fatalf("Failed to create client: %v", err)
	}

	referenceId, err := client.SendBasicEmail(context.Background(), maileroo.BasicEmailData{
		From: maileroo.NewEmail(emailFrom, "Mailer Bot"),
		To: []maileroo.EmailAddress{
			maileroo.NewEmail(emailTo, ""),
		},
		Subject: subject,
		HTML:    &htmlContent,
	})

	if err != nil {
		log.Fatalf("Failed to send email: %v", err)
	}

	log.Printf("Email sent with reference ID: %s", referenceId)
}

func parseArguments() (string, string) {
	if len(os.Args) < 3 {
		log.Fatal("Subject and HTML content arguments are required")
	}

	subject := os.Args[1]
	htmlContent := os.Args[2]

	return subject, htmlContent
}
