import resource
import subprocess
import sys
import time

start = time.monotonic()
result = subprocess.run(sys.argv[1:])
peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
print(f"MEASURE seconds={time.monotonic() - start:.2f} max_rss_kib={peak} exit={result.returncode}",
      flush=True)
sys.exit(result.returncode)
