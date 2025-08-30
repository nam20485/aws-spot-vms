# EventBridge rule to detect the 2-minute Spot interruption warning.
resource "aws_cloudwatch_event_rule" "spot_interruption_warning" {
  name        = "capture-spot-interruption-warnings"
  description = "Captures the two-minute warning before a Spot Instance is terminated"

  event_pattern = jsonencode({
    "source": ["aws.ec2"],
    "detail-type": ["EC2 Spot Instance Interruption Warning"]
  })
}

# An SNS topic to send notifications to.
# You can subscribe an email address, Lambda function, or other endpoint to this topic.
resource "aws_sns_topic" "interruption_notifications" {
  name = "spot-interruption-notifications"
}

# Connects the EventBridge rule to the SNS topic.
resource "aws_cloudwatch_event_target" "sns_target" {
  rule      = aws_cloudwatch_event_rule.spot_interruption_warning.name
  target_id = "NotifyDeveloperSNS"
  arn       = aws_sns_topic.interruption_notifications.arn
}
