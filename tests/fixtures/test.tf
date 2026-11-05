resource "null_resource" "example" {
  triggers = {
    test = "val"
  }
}
