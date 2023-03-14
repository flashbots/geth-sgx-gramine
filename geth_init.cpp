#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <unistd.h>

namespace fs = std::filesystem;

extern char **environ;

const char* log_id = "[GETH_INIT] ";

/* RA-TLS: on server, only need ra_tls_create_key_and_crt_der() to create keypair and X.509 cert */
int (*ra_tls_create_key_and_crt_der_f)(u_int8_t** der_key, size_t* der_key_size, u_int8_t** der_crt,
                                       size_t* der_crt_size);


int create_cert() {
	int ret;
	void* ra_tls_attest_lib;

	u_int8_t* der_key = NULL;
	u_int8_t* der_crt = NULL;

	char attestation_type_str[32];
	std::ifstream infile ("/dev/attestation/attestation_type", std::ifstream::in);

	if (!infile) {
		std::cout << log_id 
			<< "User requested RA-TLS attestation but cannot read SGX-specific file "
			<< "/dev/attestation/attestation_type"
			<< std::endl;
		return 1;
	}

	infile.read(attestation_type_str, sizeof attestation_type_str);
	int infile_eof = infile.eof();
	infile.close();

	if (!infile_eof || !strcmp(attestation_type_str, "none")) {
		ra_tls_attest_lib = NULL;
		ra_tls_create_key_and_crt_der_f = NULL;
	} else if (!strcmp(attestation_type_str, "dcap")) { // ignore epid !strcmp(attestation_type_str, "epid")
		ra_tls_attest_lib = dlopen("libra_tls_attest.so", RTLD_LAZY);
		if (!ra_tls_attest_lib) {
			std::cout << log_id 
				<< "User requested RA-TLS attestation but cannot find lib"
				<< std::endl;
			return 1;
		}

		char* error;
		ra_tls_create_key_and_crt_der_f = (int (*)(u_int8_t**, size_t*, u_int8_t**, size_t*))
							dlsym(ra_tls_attest_lib, "ra_tls_create_key_and_crt_der");
		if ((error = dlerror()) != NULL) {
			std::cout << log_id << error << std::endl;
			return 1;
		}
	} else {
		std::cout << log_id << "Unrecognized remote attestation type:"
			<< attestation_type_str << std::endl;
		return 1;
	}

	if (ra_tls_attest_lib) {
		std::cout << log_id << std::endl << log_id
			<< "  . Creating the RA-TLS server cert and key (using \"" << attestation_type_str
			<< "\" as attestation type)..." << std::endl;
		fflush(stdout);

		size_t der_key_size;
		size_t der_crt_size;

		// make sure cert and key paths are set
		if (!getenv("RATLS_CRT_PATH")) {
			setenv("RATLS_CRT_PATH", "/tmp/tlscert.der", 0);
		}
		if (!getenv("RATLS_KEY_PATH")) {
			setenv("RATLS_KEY_PATH", "/tmp/tlskey.der", 0);
		}

		ret = (*ra_tls_create_key_and_crt_der_f)(&der_key, &der_key_size, &der_crt, &der_crt_size);
		if (ret != 0) {
			std::cout << log_id << " failed" << std::endl << log_id
				<< "  !  ra_tls_create_key_and_crt_der returned " << ret << std::endl;
			goto exit;
		}

		std::ofstream der_key_file (getenv("RATLS_KEY_PATH"), std::ofstream::out);
		if (der_key_file) {
			der_key_file.write(reinterpret_cast<char*>(der_key), der_key_size);
			if (der_key_file.fail()) {
				std::cout << log_id << "Writing to der_key file failed: "
					<< std::strerror(errno) << std::endl;
				goto exit;
			}
			der_key_file.close();
		} else {
			std::cout << log_id << "Cannot open der_key file at \"" << getenv("RATLS_KEY_PATH")
				<< "\" for writing: " << std::strerror(errno) << std::endl;
			goto exit;
		}

		std::ofstream der_crt_file (getenv("RATLS_CRT_PATH"), std::ofstream::out);
		if (der_crt_file) {
			der_crt_file.write(reinterpret_cast<char*>(der_crt), der_crt_size);
			if (der_crt_file.fail()) {
				std::cout << log_id << "Writing to der_crt file failed: "
					<< std::strerror(errno) << std::endl;
				goto exit;
			}
			der_crt_file.close();
		} else {
			std::cout << log_id << "Cannot open der_crt file at \"" << getenv("RATLS_CRT_PATH")
				<< "\" for writing: " << std::strerror(errno) << std::endl;
			goto exit;
		}

		std::cout << log_id << "ok" << std::endl;
	}

	exit:
	if (ra_tls_attest_lib)
		dlclose(ra_tls_attest_lib);

	free(der_key);
	free(der_crt);

	return ret;
}

int main(int argc, char **argv)
{
	int ret = create_cert();

	if (ret != 0) {
		std::cout << log_id << "creating RA-TLS attestation certificate failed. "
			<< "Aborting..."
			<< std::endl;
		exit(ret);
	}

	const char* copy = getenv("COPY_DATABASE");

	if ( copy && strcmp(copy,"true") == 0 ) {
		const char* source = getenv("DATABASE_SOURCE") ?
		       getenv("DATABASE_SOURCE") : "data/synced_state";
		const char* target = getenv("DATABASE_TARGET") ?
			getenv("DATABASE_TARGET") : "/root/.ethereum";

		std::cout << log_id << "Copying ethereum database." << std::endl;

		fs::copy(source, target, fs::copy_options::recursive);
		if (errno == EDOM) {
			std::cout << log_id
				  << "Copy failed: " 
				  << std::strerror(errno) 
				  << std::endl;
			exit(errno);
		}
	}

        execve(getenv("GETH_BIN"), argv, environ);
        std::cout << log_id << "execve failed: " << std::strerror(errno) << std::endl;
	exit(1);
}
