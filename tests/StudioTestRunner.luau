local RunService = game:GetService("RunService")

print("[StudioTestRunner] starting ECSR framework verification")
RunService:Run()
task.wait(8)
RunService:Stop()
print("[StudioTestRunner] verification finished")

