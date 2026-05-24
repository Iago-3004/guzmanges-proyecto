package com.guzmanges.api;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@EnableScheduling
public class GuzmangesApiApplication {

	public static void main(String[] args) {
		SpringApplication.run(GuzmangesApiApplication.class, args);
	}

}
