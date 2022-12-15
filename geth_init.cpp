#include <unistd.h>
#include <cstdlib>
#include <iostream>
#include <filesystem>
#include <cstring>

namespace fs = std::filesystem;

int main(int argc, char **argv, char **envp)
{
	const char* copy = getenv("COPY_DATABASE");

	if ( copy && strcmp(copy,"true") == 0 ) {
		const char* source = getenv("DATABASE_SOURCE") ?
		       getenv("DATABASE_SOURCE") : "/root/.ethereum.synced";
		const char* target = getenv("DATABASE_TARGET") ?
			getenv("DATABASE_TARGET") : "/root/.ethereum";

		std::cout << "[GETH_INIT] Copying ethereum database." << std::endl;

		fs::copy(source, target, fs::copy_options::recursive);
		if (errno == EDOM) {
			std::cout << "[GETH_INIT] Copy failed: " 
				  << std::strerror(errno) 
				  << std::endl;
		}
	}

        execve(getenv("GETH_BIN"), argv, envp);
        std::cout << "[GETH_INIT] execve failed: " << std::strerror(errno) << std::endl;
	exit(1);
}
