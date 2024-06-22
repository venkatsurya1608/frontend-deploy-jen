module "frontend" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"    # give only frontend or var.common_tags.Component
  instance_type          = "t3.micro"
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value] 
  # convert StringList to list and get first element
  subnet_id = local.public_subnet_id
  ami = data.aws_ami.ami_info.id
  

  tags = merge(
    var.common_tags,
    {
        Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"    
    }
  )
}

# resource "null_resource" "frontend" {
#     triggers = {
#         instance_id = module.frontend.id   # this will triggered everytime instances is created 
#     } 

#     connection {
#         type     = "ssh"
#         user     = "ec2-user"
#         password = "DevOps321"
#         host     = module.frontend.public_ip
#     }
#     provisioner "file" {
#         source      = "frontend.sh"
#         destination = "/tmp/frontend.sh"
#     }


#     provisioner "remote-exec" {
#         inline = [
#             "chmod +x /tmp/frontend.sh",
#             "sudo sh /tmp/frontend.sh ${var.common_tags.Component}-${var.environment}"
#         ]
#     } 
# }

resource "null_resource" "frontend" {
    triggers = {
      instance_id = module.frontend.id # this will be triggered everytime instance is created
    }

    connection {
        type     = "ssh"
        user     = "ec2-user"
        password = "DevOps321"
        host     = module.frontend.private_ip
    }

    provisioner "file" {
        source      = "${var.common_tags.Component}.sh"
        destination = "/tmp/${var.common_tags.Component}.sh"
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x /tmp/${var.common_tags.Component}.sh",
            "sudo sh /tmp/${var.common_tags.Component}.sh ${var.common_tags.Component} ${var.environment} ${var.app_version}"
        ]
    } 
}


# stop server when only null resource provisioning is completed  enduke depends on pettamu
resource "aws_ec2_instance_state" "frontend" {    #ec2 instance state terraform
  instance_id = module.frontend.id
  state       = "stopped"
  depends_on = [null_resource.frontend ]
}

resource "aws_ami_from_instance" "frontend" {             #aws ami from instance terraform
  name               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  source_instance_id = module.frontend.id
  depends_on = [ aws_ec2_instance_state.frontend ]
}

resource "null_resource" "frontend_delete" {    # ???
    triggers = {
        instance_id = module.frontend.id
    } 

    provisioner "local-exec" {
        command = "aws ec2 terminate-instances --instance-ids ${module.frontend.id}"   #instance nee terminate chesthunam
    } 
    depends_on = [ aws_ami_from_instance.frontend ]
}

resource "aws_lb_target_group" "frontend" {
  name     = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value       #aws elb target group with health check terraform

  health_check {
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-299"
  }
}

resource "aws_launch_template" "frontend" {
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  image_id = data.aws_ami.ami_info.id

  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t2.micro"
  update_default_version = true          # sets the latest version to default  vasthundi
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
        var.common_tags,
        {
            Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
        }
    )
  }
}

resource "aws_autoscaling_group" "frontend" {
  name                      = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  max_size                  = 5   # 5 means max 5 instances run avvali ani 
  min_size                  = 1   # minimum 1 instance run avvali ani
  health_check_grace_period = 60
  health_check_type         = "ELB"
  desired_capacity          = 1   # starting 1 instance create kavali ani
  target_group_arns = [aws_lb_target_group.frontend.arn]   # target group ki auto scaling add cheyali
  launch_template {                             # launch template version add chesamu
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }
  vpc_zone_identifier       = split(",", data.aws_ssm_parameter.public_subnet_ids.value)

  instance_refresh {
    strategy = "Rolling"       # here rolling means create instance and delete instance refresh avthundali
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    propagate_at_launch = true
  }
    timeouts {
    delete = "15m"
  }

  tag {
    key                 = "Project"
    value               = "${var.project_name}"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_policy" "frontend" {
  name                   = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.frontend.name
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 10.0   # your wish
  }
}

resource "aws_lb_listener_rule" "frontend" {
  listener_arn = data.aws_ssm_parameter.web_alb_listener_arn_https.value
  priority     = 100    # less number will be first vaildated

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn   
  }

  condition {
    host_header {
      values = ["web-${var.environment}.${var.zone_name}"]
    }
  }
}